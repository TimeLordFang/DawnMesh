import 'dart:async';
import 'dart:typed_data';

import 'package:dawn_mesh/core/audio/audio_io.dart';
import 'package:dawn_mesh/core/protocol/frame.dart';
import 'package:dawn_mesh/core/protocol/frame_type.dart';
import 'package:dawn_mesh/core/security/session_crypto.dart';
import 'package:dawn_mesh/core/security/session_handshake.dart';
import 'package:dawn_mesh/core/session/room_session.dart';
import 'package:flutter_test/flutter_test.dart';

Frame _heartbeat(int seq) => Frame(
  type: FrameType.heartbeat,
  senderId: 2,
  seq: seq,
  payload: Uint8List(0),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'outgoing crypto yields to I/O without losing or reordering work',
    () async {
      final session = RoomSession(audioIo: MockAudioIo(), selfNickname: 'Peer');
      addTearDown(session.dispose);
      session.secureCodec = SecureFrameCodec(
        await SessionCipher.fromKey(Uint8List(32)),
      );
      final sent = <Frame>[];
      session.onSendFrame = sent.add;
      final timer = Completer<int>();
      Timer.run(() => timer.complete(sent.length));
      final work = [
        for (var i = 1; i <= 64; i++) session.sendFrame(_heartbeat(i)),
      ];
      expect(await timer.future, lessThan(64));
      await Future.wait(work);
      expect(sent, hasLength(64));
      final receiver = SecureFrameCodec(
        await SessionCipher.fromKey(Uint8List(32)),
      );
      final sequences = [
        for (final frame in sent) (await receiver.open(frame)).seq,
      ];
      expect(sequences, List.generate(64, (i) => i + 1));
    },
  );

  test(
    'incoming crypto yields to I/O while preserving receive order',
    () async {
      final session = RoomSession(audioIo: MockAudioIo(), selfNickname: 'Peer');
      addTearDown(session.dispose);
      session.secureCodec = SecureFrameCodec(
        await SessionCipher.fromKey(Uint8List(32)),
      );
      final sender = SecureFrameCodec(
        await SessionCipher.fromKey(Uint8List(32)),
      );
      final packets = [
        for (var i = 1; i <= 64; i++) await sender.seal(_heartbeat(i)),
      ];
      final completed = <int>[];
      final timer = Completer<int>();
      Timer.run(() => timer.complete(completed.length));
      final work = [
        for (final packet in packets)
          session
              .handleIncomingFrame(packet)
              .then((_) => completed.add(packet.seq)),
      ];
      expect(await timer.future, lessThan(64));
      await Future.wait(work);
      expect(completed, List.generate(64, (i) => i + 1));
    },
  );
}
