import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dawn_mesh/core/audio/audio_io.dart';
import 'package:dawn_mesh/core/protocol/frame.dart';
import 'package:dawn_mesh/core/protocol/frame_type.dart';
import 'package:dawn_mesh/core/protocol/payloads/join_request.dart';
import 'package:dawn_mesh/core/security/room_invite.dart';
import 'package:dawn_mesh/core/session/room_session.dart';
import 'package:dawn_mesh/core/transport/lan_transport.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingLanTransport extends LanTransport {
  _RecordingLanTransport(this.wire) : super(controlOnly: true);
  final List<Frame> wire;
  @override
  void send(Frame frame, {bool realtime = false}) {
    wire.add(frame);
    super.send(frame, realtime: realtime);
  }
}

Future<void> _until(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('room capacity');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Wi-Fi/fusion allocate 16 identities, reject 17 and preserve reconnect identity; Bluetooth remains 6', () async {
    for (final mode in RoomMode.values) {
      final session = RoomSession(
        audioIo: MockAudioIo(),
        selfNickname: 'Host',
        mode: mode,
      );
      await session.createRoom(startAudio: false);
      final limit = session.isBluetooth ? 6 : 16;
      for (var i = 2; i <= limit + 1; i++) {
        await session.handleIncomingFrame(
          Frame(
            type: FrameType.joinReq,
            senderId: 0,
            seq: i,
            payload: JoinRequestPayload(
              nickname: 'M$i',
              sessionToken: Uint8List(16)..[0] = i,
            ).encode(),
          ),
        );
      }
      expect(session.members, hasLength(limit));
      expect(session.members.last.memberId, limit);
      await session.handleIncomingFrame(
        Frame(
          type: FrameType.joinReq,
          senderId: 0,
          seq: 100,
          payload: JoinRequestPayload(
            nickname: 'Renamed',
            sessionToken: Uint8List(16)..[0] = limit,
          ).encode(),
        ),
      );
      expect(session.members, hasLength(limit));
      expect(session.members.last.memberId, limit);
      expect(session.members.last.nickname, 'Renamed');
      await session.dispose();
    }
  });

  test(
    '16 protected Wi-Fi phones get full long-name rosters, audio and rejoin',
    () async {
      final nodes = <RoomSession>[];
      final links = <LanTransport>[];
      final wire = <Frame>[];
      addTearDown(() async {
        for (final session in nodes.reversed) {
          await session.dispose();
        }
        for (final link in links) {
          await link.dispose();
        }
      });
      final invite = RoomInvite.parse('1234');
      Future<RoomSession> make(int id, {bool host = false}) async {
        final session = RoomSession(
          audioIo: MockAudioIo(),
          selfNickname: '$id${'声' * 20}',
        );
        final link = _RecordingLanTransport(wire);
        nodes.add(session);
        links.add(link);
        session.attachTransport(link, reconnect: link.reconnectClient);
        await session.protectWithInvite(invite);
        expect(
          host
              ? await link.startHost()
              : await link.startClient(
                  hostAddress: InternetAddress.loopbackIPv4,
                ),
          true,
        );
        if (host) {
          await session.createRoom(startAudio: false);
        } else {
          await session.joinRoom(startAudio: false);
          await _until(() => session.state == RoomState.inRoom);
        }
        return session;
      }

      final host = await make(1, host: true);
      for (var id = 2; id <= 16; id++) {
        await make(id);
      }
      await _until(() => nodes.every((node) => node.members.length == 16));
      expect(links.first.peerCount, 15);
      for (final node in nodes) {
        expect(node.members.map((member) => member.memberId).toSet(), {
          for (var id = 1; id <= 16; id++) id,
        });
        expect(node.members.last.nickname, '16${'声' * 20}');
      }
      await nodes.last.sendFrame(
        Frame(
          type: FrameType.audio,
          senderId: 16,
          seq: 1000,
          payload: Uint8List.fromList([7, 8, 9]),
        ),
      );
      await _until(
        () => (nodes[1].audioIo as MockAudioIo).submittedFrames.isNotEmpty,
      );
      expect((nodes[1].audioIo as MockAudioIo).submittedFrames, hasLength(1));
      await links.last.stop();
      await _until(() => links.first.peerCount == 14);
      nodes.last.triggerDisconnect();
      await _until(
        () => nodes.last.state == RoomState.inRoom && links.last.peerCount == 1,
      );
      expect(nodes.last.selfMemberId, 16);
      expect(host.members, hasLength(16));
      expect(wire, isNotEmpty);
      expect(
        wire.every(
          (frame) =>
              frame.type == FrameType.sealed ||
              frame.type == FrameType.handshakeHello ||
              frame.type == FrameType.handshakeConfirm,
        ),
        true,
      );
      final extra = LanTransport(controlOnly: true);
      addTearDown(extra.dispose);
      await extra.startClient(hostAddress: InternetAddress.loopbackIPv4);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(extra.peerCount, 0);
      expect(links.first.peerCount, 15);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
