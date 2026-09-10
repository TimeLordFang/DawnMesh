import 'dart:async';
import 'dart:typed_data';

import 'package:dawn_mesh/core/audio/audio_io.dart';
import 'package:dawn_mesh/core/protocol/frame.dart';
import 'package:dawn_mesh/core/protocol/frame_type.dart';
import 'package:dawn_mesh/core/protocol/payloads/roster.dart';
import 'package:dawn_mesh/core/session/room_session.dart';
import 'package:dawn_mesh/core/transport/room_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transport is told that audio may be dropped while control stays reliable', () async {
    final transport = _FakeTransport();
    final session = RoomSession(audioIo: MockAudioIo(), selfNickname: '实时成员');
    session.attachTransport(transport, reconnect: () async => false);
    addTearDown(() async {
      await session.dispose();
      await transport.dispose();
    });

    await session.sendFrame(
      Frame(type: FrameType.audio, senderId: 1, seq: 1, payload: Uint8List(8)),
    );
    await session.sendFrame(
      Frame(type: FrameType.heartbeat, senderId: 1, seq: 2, payload: Uint8List(0)),
    );

    expect(transport.sentRealtime, [true, false]);
  });

  test(
    'a physical disconnect rebuilds the link and rejoins the room',
    () async {
      final transport = _FakeTransport();
      final session = RoomSession(audioIo: MockAudioIo(), selfNickname: '重连成员');
      var reconnectCalls = 0;
      session.attachTransport(
        transport,
        reconnect: () async {
          reconnectCalls++;
          return true;
        },
      );

      addTearDown(() async {
        await session.dispose();
        await transport.dispose();
      });

      await session.joinRoom(startAudio: false);
      transport.emit(_roster());
      await _until(() => session.state == RoomState.inRoom);

      transport.disconnect('remote_eof');
      await _until(() => session.state == RoomState.reconnecting);

      await _until(
        () => reconnectCalls == 1,
        timeout: const Duration(seconds: 2),
      );
      await _until(
        () =>
            transport.sent
                .where((frame) => frame.type == FrameType.joinReq)
                .length >=
            2,
      );
      expect(session.members, isEmpty);
      transport.emit(_roster());
      await _until(() => session.state == RoomState.inRoom);

      expect(reconnectCalls, 1);
      expect(session.selfMemberId, 2);
    },
  );
}

Frame _roster() => Frame(
  type: FrameType.roster,
  senderId: 1,
  seq: 1,
  payload:
      RosterPayload(
        hostId: 1,
        members: [
          RosterMember(memberId: 1, flags: 1, nickname: '房主'),
          RosterMember(memberId: 2, flags: 0, nickname: '重连成员'),
        ],
      ).encode(),
);

Future<void> _until(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _FakeTransport implements RoomTransport {
  final _incoming = StreamController<Frame>.broadcast(sync: true);
  final _disconnections = StreamController<TransportDisconnection>.broadcast(
    sync: true,
  );
  final List<Frame> sent = [];
  final List<bool> sentRealtime = [];

  @override
  Stream<Frame> get incoming => _incoming.stream;

  @override
  Stream<TransportDisconnection> get disconnections => _disconnections.stream;

  @override
  int get peerCount => 1;

  void emit(Frame frame) => _incoming.add(frame);

  void disconnect(String reason) =>
      _disconnections.add(TransportDisconnection(reason: reason));

  @override
  void send(Frame frame, {bool realtime = false}) {
    sent.add(frame);
    sentRealtime.add(realtime);
  }

  @override
  Future<void> flush() async {}

  @override
  void updateSelfMemberId(int id) {}

  @override
  void updateKnownMemberIds(Set<int> ids) {}

  @override
  bool get supportsHostTransfer => false;

  @override
  Future<bool> becomeHost() async => false;

  @override
  Future<bool> reconnectToHost(String endpoint) async => false;

  @override
  Map<int, String> get peerEndpoints => const {};

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _incoming.close();
    await _disconnections.close();
  }
}
