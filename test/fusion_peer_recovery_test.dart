import 'dart:async';
import 'dart:typed_data';

import 'package:dawn_mesh/core/audio/audio_io.dart';
import 'package:dawn_mesh/core/internet/internet_audio_profile.dart';
import 'package:dawn_mesh/core/protocol/frame.dart';
import 'package:dawn_mesh/core/protocol/frame_type.dart';
import 'package:dawn_mesh/core/protocol/payloads/roster.dart';
import 'package:dawn_mesh/core/security/room_invite.dart';
import 'package:dawn_mesh/core/security/session_crypto.dart';
import 'package:dawn_mesh/core/security/session_handshake.dart';
import 'package:dawn_mesh/core/session/room_session.dart';
import 'package:dawn_mesh/core/transport/room_transport.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

class Link extends RoomTransport {
  final received = StreamController<Frame>.broadcast();
  final sent = <Frame>[];
  int reconnectCalls = 0;
  Completer<bool>? reconnectResult;
  @override
  Stream<Frame> get incoming => received.stream;
  @override
  int get peerCount => 0;
  @override
  bool get supportsHostTransfer => false;
  @override
  Map<int, String> get peerEndpoints => {};
  @override
  void send(Frame frame, {bool realtime = false}) => sent.add(frame);
  @override
  void updateSelfMemberId(int id) {}
  @override
  Future<bool> becomeHost() async => false;
  @override
  Future<bool> reconnectToHost(String endpoint) async => false;
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() => received.close();
  Future<bool> reconnect() async {
    reconnectCalls++;
    return reconnectResult?.future ?? true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RoomSession session;
  late MockAudioIo audio;
  late Link link;
  late SecureFrameCodec remote;
  late DateTime now;
  var seq = 0;
  Future<void> receive(FrameType type, int id, [Uint8List? payload]) async =>
      session.handleIncomingFrame(
        await remote.seal(
          Frame(
            type: type,
            senderId: id,
            seq: seq++,
            payload: payload ?? Uint8List(0),
          ),
        ),
      );
  setUp(() async {
    now = DateTime.now();
    seq = 0;
    audio = MockAudioIo();
    link = Link();
    session = RoomSession(
      audioIo: audio,
      selfNickname: 'A',
      mode: RoomMode.fusion,
      now: () => now,
    );
    session.attachTransport(link, reconnect: link.reconnect);
    // Start from the admitted encrypted protocol boundary; PAKE itself is
    // exercised separately by the real-socket fusion admission tests.
    session.roomInvite = RoomInvite.parse('1234');
    session.secureCodec = SecureFrameCodec(
      await SessionCipher.fromKey(Uint8List(32)),
    );
    remote = SecureFrameCodec(await SessionCipher.fromKey(Uint8List(32)));
    await session.joinRoom(startAudio: false);
    await receive(
      FrameType.admission,
      1,
      Uint8List.fromList([2, ...session.sessionToken]),
    );
    await receive(
      FrameType.roster,
      1,
      RosterPayload(
        hostId: 1,
        members: [
          RosterMember(memberId: 1, flags: 1, nickname: 'Host'),
          RosterMember(memberId: 2, flags: 0, nickname: 'A'),
          RosterMember(memberId: 3, flags: 0, nickname: 'B'),
        ],
      ).encode(),
    );
    await session.startAudio();
  });
  tearDown(() async {
    await session.dispose();
    await link.dispose();
  });

  test(
    'host silence does not interrupt authenticated member-to-member voice',
    () async {
      final codec = session.secureCodec;
      now = now.add(const Duration(seconds: 20));
      await receive(FrameType.heartbeat, 3);
      session.checkHostFailover();
      expect(session.fusionHostUnavailable, true);
      expect(session.state, RoomState.inRoom);
      expect(session.secureCodec, same(codec));
      await receive(FrameType.audio, 3, Uint8List.fromList([1, 2, 3]));
      expect(audio.submittedFrames, hasLength(1));
      final before = link.sent.length;
      await session.fusionAudio.select(InternetAudioProfile.clarity);
      expect(audio.bitrate, session.audioBitrate);
      expect(audio.isRecording, true);
      expect(session.voiceMode, VoiceMode.pushToTalk);
      audio.emitEncodedFrame(Uint8List.fromList([3, 2, 1]));
      await Future<void>.delayed(Duration.zero);
      expect(
        link.sent,
        hasLength(before),
      ); // Quality switching never opens PTT.
    },
  );

  test(
    'reconnect retains admission; only an authenticated known peer resumes it',
    () async {
      final codec = session.secureCodec;
      session.setPtt(true);
      now = now.add(const Duration(seconds: 20));
      session.checkHostFailover();
      expect(session.state, RoomState.reconnecting);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(link.reconnectCalls, 1);
      expect(session.secureCodec, same(codec));
      expect(session.selfMemberId, 2);
      expect(session.members, hasLength(3));
      expect(session.isPttPressed, false);
      await receive(FrameType.heartbeat, 6);
      expect(session.state, RoomState.reconnecting);
      await session.handleIncomingFrame(
        Frame(
          type: FrameType.heartbeat,
          senderId: 3,
          seq: 999,
          payload: Uint8List(0),
        ),
      );
      expect(session.state, RoomState.reconnecting);
      await receive(FrameType.heartbeat, 3);
      expect(session.state, RoomState.inRoom);
      expect(session.isPttPressed, false);
      expect(session.secureCodec, same(codec));
    },
  );

  test(
    'only loss of all peers expires the 30-minute recovery window',
    () async {
      // Even a stalled platform reconnect must not bypass the deadline.
      link.reconnectResult = Completer<bool>();
      await session.sendFusionControl(Uint8List(0));
      now = now.add(const Duration(seconds: 20));
      fakeAsync((clock) {
        session.checkHostFailover();
        now = now.add(const Duration(minutes: 29));
        clock.elapse(const Duration(minutes: 29));
        clock.flushMicrotasks();
        expect(session.state, RoomState.reconnecting);
        expect(session.hasFusionIdentity, true);
        now = now.add(const Duration(minutes: 1));
        clock.elapse(const Duration(minutes: 1));
        clock.flushMicrotasks();
        expect(session.state, RoomState.disconnected);
        expect(audio.isRecording, false);
      });
      await receive(FrameType.heartbeat, 3);
      expect(session.state, RoomState.disconnected);
    },
  );
}
