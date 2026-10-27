import 'dart:async';
import 'dart:typed_data';

import 'package:dawn_mesh/core/audio/audio_io.dart';
import 'package:dawn_mesh/core/protocol/frame.dart';
import 'package:dawn_mesh/core/protocol/frame_type.dart';
import 'package:dawn_mesh/core/security/member_identity.dart';
import 'package:dawn_mesh/core/security/room_admission.dart';
import 'package:dawn_mesh/core/security/room_invite.dart';
import 'package:dawn_mesh/core/session/room_session.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _expectRecovery(bool Function(Frame, bool) shouldDrop) async {
  final host = RoomSession(audioIo: MockAudioIo(), selfNickname: 'Host');
  final guest = RoomSession(audioIo: MockAudioIo(), selfNickname: 'Guest');
  addTearDown(host.dispose);
  addTearDown(guest.dispose);
  final invite = RoomInvite.parse('1234');
  await host.protectWithInvite(invite, identity: await MemberIdentity.create());
  await guest.protectWithInvite(
    invite,
    identity: await MemberIdentity.create(),
  );
  var dropped = false;
  void deliver(Frame frame, RoomSession target, bool fromHost) {
    if (!dropped && shouldDrop(frame, fromHost)) {
      dropped = true;
      return;
    }
    unawaited(target.handleIncomingFrame(frame));
  }

  host.onSendFrame = (frame) => deliver(frame, guest, true);
  guest.onSendFrame = (frame) => deliver(frame, host, false);
  await host.createRoom(startAudio: false);
  await guest.joinRoom(startAudio: false);
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (guest.state != RoomState.inRoom && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(dropped, true);
  expect(guest.state, RoomState.inRoom);
  expect(host.members, hasLength(2));
  expect(guest.members, hasLength(2));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (var lostKind = 1; lostKind <= 4; lostKind++) {
    test('admission recovers a lost PAKE packet at stage $lostKind', () async {
      await _expectRecovery(
        (frame, _) =>
            (frame.type == FrameType.handshakeHello ||
                frame.type == FrameType.handshakeConfirm) &&
            frame.payload[1] == lostKind,
      );
    });
  }
  for (final fromHost in [false, true]) {
    test(
      'admission repairs a lost sealed ${fromHost ? 'response' : 'join'}',
      () async {
        await _expectRecovery(
          (frame, senderIsHost) =>
              frame.type == FrameType.sealed && senderIsHost == fromHost,
        );
      },
    );
  }

  test('a completed hello replay cannot block a fresh admission', () async {
    final hostFrames = <Frame>[], guestFrames = <Frame>[];
    var ready = 0;
    final host = RoomAdmission(
      passwordScalar: BigInt.one,
      token: Uint8List(16),
      identity: await MemberIdentity.create(),
      send: hostFrames.add,
      onReady: (_) async {},
    );
    final guest = RoomAdmission(
      passwordScalar: BigInt.one,
      token: Uint8List(16)..[0] = 2,
      identity: await MemberIdentity.create(),
      send: guestFrames.add,
      onReady: (_) async {
        ready++;
      },
    );
    addTearDown(host.close);
    addTearDown(guest.close);
    await host.startHost();
    guest.startClient();
    final originalHello = guestFrames.last;
    await host.handle(originalHello);
    await guest.handle(hostFrames.last);
    await host.handle(guestFrames.last);
    await guest.handle(hostFrames.last);
    expect(ready, 1);
    await host.handle(originalHello);
    hostFrames.clear();
    guest.startClient();
    await host.handle(guestFrames.last);
    expect(hostFrames, isNotEmpty);
    await guest.handle(hostFrames.last);
    await host.handle(guestFrames.last);
    await guest.handle(hostFrames.last);
    expect(ready, 2);
  });
  test('handshake repair is bounded and uses fresh transport ids', () async {
    final frames = <Frame>[];
    final guest = RoomAdmission(
      passwordScalar: BigInt.one,
      token: Uint8List(16)..[0] = 2,
      identity: await MemberIdentity.create(),
      send: frames.add,
      onReady: (_) async {},
    );
    addTearDown(guest.close);
    guest.startClient();
    for (var i = 0; i < 20; i++) {
      guest.retryPendingHandshake();
    }
    expect(frames, hasLength(6));
    expect(frames.map((frame) => frame.seq).toSet(), hasLength(6));
    expect(frames.every((frame) => frame.seq >> 8 == 8), true);
    for (final frame in frames) {
      expect(frame.payload, frames.first.payload);
    }
    guest.close();
    guest.retryPendingHandshake();
    expect(frames, hasLength(6));
  });
}
