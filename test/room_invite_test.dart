import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:dawn_mesh/core/audio/audio_io.dart';
import 'package:dawn_mesh/core/protocol/frame.dart';
import 'package:dawn_mesh/core/protocol/frame_type.dart';
import 'package:dawn_mesh/core/protocol/payloads/roster.dart';
import 'package:dawn_mesh/core/security/room_invite.dart';
import 'package:dawn_mesh/core/security/session_crypto.dart';
import 'package:dawn_mesh/core/security/session_handshake.dart';
import 'package:dawn_mesh/core/session/room_session.dart';
import 'package:dawn_mesh/core/transport/lan_transport.dart';

Future<void> until(bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 3));
  while (!condition() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

void main() {
  test('invitation is canonical, random, and redacted', () {
    final invite = RoomInvite.generate();
    expect(invite.code.length, 4);
    expect(RoomInvite.parse('0012').code, '0012');
    expect(RoomInvite.parse('000123').code, '000123');
    expect(RoomInvite.parse(' ${invite.code} ').code, invite.code);
    for (final invalid in ['123', '12345', '1234567', '１２３４', '12a4']) {
      expect(() => RoomInvite.parse(invalid), throwsFormatException);
    }
    expect(invite.toString(), isNot(contains(invite.code)));
    expect(() => RoomInvite.parse('password'), throwsFormatException);
    expect(
      () => RoomInvite.parse('AAAAAAAAAAAAAAAAAAAAAB'),
      throwsFormatException,
    );
  });

  test(
    'wrong key, modified ciphertext, and concurrent replay are rejected',
    () async {
      final sender = SecureFrameCodec(
        await SessionCipher.fromKey(Uint8List(32)),
      );
      final receiver = SecureFrameCodec(
        await SessionCipher.fromKey(Uint8List(32)),
      );
      final wrong = SecureFrameCodec(
        await SessionCipher.fromKey(Uint8List(32)..[0] = 1),
      );
      final sealed = await sender.seal(
        Frame(
          type: FrameType.chat,
          senderId: 1,
          seq: 0,
          payload: Uint8List.fromList(utf8.encode('private')),
        ),
      );
      await expectLater(wrong.open(sealed), throwsA(anything));
      final modified = Frame(
        type: sealed.type,
        senderId: 1,
        seq: 0,
        payload: Uint8List.fromList(sealed.payload)..[20] ^= 1,
      );
      await expectLater(receiver.open(modified), throwsA(anything));
      final results = await Future.wait(
        List.generate(2, (_) async {
          try {
            await receiver.open(sealed);
            return true;
          } catch (_) {
            return false;
          }
        }),
      );
      expect(results.where((accepted) => accepted).length, 1);
    },
  );

  test('old counters remain rejected after replay window advances', () async {
    final sender = await SessionCipher.fromKey(Uint8List(32));
    final receiver = await SessionCipher.fromKey(Uint8List(32));
    final first = await sender.encrypt(Uint8List.fromList([1]));
    await receiver.decrypt(first);
    for (var i = 0; i <= SessionCipher.replayWindowSize; i++) {
      await receiver.decrypt(await sender.encrypt(Uint8List.fromList([2])));
    }
    await expectLater(receiver.decrypt(first), throwsStateError);
  });

  test(
    'captured roster cannot admit a fresh client without its challenge',
    () async {
      final invite = RoomInvite.generate();
      final hostCodec = SecureFrameCodec(
        await SessionCipher.fromKey(Uint8List(32)),
      );
      final guest = RoomSession(audioIo: MockAudioIo(), selfNickname: 'Guest');
      addTearDown(guest.dispose);
      await guest.protectWithInvite(invite);
      await guest.joinRoom(startAudio: false);
      // Isolate post-PAKE membership confirmation from the PAKE tests.
      guest.secureCodec = SecureFrameCodec(
        await SessionCipher.fromKey(Uint8List(32)),
      );
      final roster = Frame(
        type: FrameType.roster,
        senderId: 1,
        seq: 1,
        payload: RosterPayload(
          hostId: 1,
          members: [
            RosterMember(memberId: 1, flags: 1, nickname: 'Host'),
            RosterMember(memberId: 2, nickname: 'Guest'),
          ],
        ).encode(),
      );
      await guest.handleIncomingFrame(await hostCodec.seal(roster));
      expect(guest.state, RoomState.connecting);
      await guest.handleIncomingFrame(
        await hostCodec.seal(
          Frame(
            type: FrameType.admission,
            senderId: 1,
            seq: 2,
            payload: Uint8List.fromList([2, ...Uint8List(16)]),
          ),
        ),
      );
      await guest.handleIncomingFrame(await hostCodec.seal(roster));
      expect(guest.state, RoomState.connecting);
      await guest.handleIncomingFrame(
        await hostCodec.seal(
          Frame(
            type: FrameType.admission,
            senderId: 1,
            seq: 3,
            payload: Uint8List.fromList([2, ...guest.sessionToken]),
          ),
        ),
      );
      await guest.handleIncomingFrame(await hostCodec.seal(roster));
      expect(guest.state, RoomState.inRoom);
    },
  );

  test('real TCP protected rooms carry chat, history and audio; wrong invite cannot join', () async {
    final invite = RoomInvite.generate();
    final wire = <Frame>[];
    final sessions = <RoomSession>[];
    final subs = <StreamSubscription<Frame>>[];
    addTearDown(() async {
      for (final sub in subs) {
        await sub.cancel();
      }
      for (final session in sessions.reversed) {
        await session.dispose();
      }
    });
    Future<RoomSession> make(
      String name,
      RoomInvite key, {
      bool host = false,
    }) async {
      final session = RoomSession(audioIo: MockAudioIo(), selfNickname: name);
      sessions.add(session);
      final transport = LanTransport(controlOnly: true);
      session.transport = transport;
      await session.protectWithInvite(key);
      session.onSendFrame = (frame) {
        wire.add(frame);
        transport.send(frame);
      };
      subs.add(transport.incoming.listen(session.handleIncomingFrame));
      expect(
        host
            ? await transport.startHost()
            : await transport.startClient(
                hostAddress: InternetAddress.loopbackIPv4,
              ),
        isTrue,
      );
      if (host) {
        await session.createRoom(startAudio: false);
      } else {
        await session.joinRoom(startAudio: false);
      }
      return session;
    }

    final host = await make('Host', invite, host: true);
    final guest = await make('Guest', invite);
    await until(() => guest.state == RoomState.inRoom);
    final message = '秘密${'x' * 314}'; // 320 UTF-8 bytes
    await host.sendChat(message);
    await until(() => guest.chatMessages.any((m) => m.text == message));
    await expectLater(host.sendChat('$message!'), throwsArgumentError);
    final lateGuest = await make('Later', invite);
    await until(() => lateGuest.chatMessages.any((m) => m.text == message));
    await guest.sendChat('guest secret');
    await until(
      () =>
          host.chatMessages.any((m) => m.text == 'guest secret') &&
          lateGuest.chatMessages.any((m) => m.text == 'guest secret'),
    );
    await guest.sendFrame(
      Frame(
        type: FrameType.audio,
        senderId: guest.selfMemberId,
        seq: 90,
        payload: Uint8List.fromList([11, 22, 33]),
      ),
    );
    await until(
      () => (lateGuest.audioIo as MockAudioIo).submittedFrames.isNotEmpty,
    );
    expect(
      Frame.decode((lateGuest.audioIo as MockAudioIo).submittedFrames.single)!
          .payload,
      [11, 22, 33],
    );
    final wrong = await make(
      'Wrong',
      RoomInvite.parse(invite.code == '0000' ? '0001' : '0000'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(wrong.state, RoomState.connecting);
    expect(host.members.length, 3);
    expect(wire, isNotEmpty);
    expect(
      wire.every(
        (frame) =>
            frame.type == FrameType.sealed ||
            frame.type == FrameType.handshakeHello ||
            frame.type == FrameType.handshakeConfirm,
      ),
      isTrue,
    );
    expect(
      wire.any(
        (frame) => latin1.decode(frame.encode()).contains('guest secret'),
      ),
      isFalse,
    );
  });
}
