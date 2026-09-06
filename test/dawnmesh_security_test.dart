import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/audio/audio_io.dart';
import 'package:sunset_ripple/core/protocol/frame.dart';
import 'package:sunset_ripple/core/protocol/frame_type.dart';
import 'package:sunset_ripple/core/protocol/payloads/join_request.dart';
import 'package:sunset_ripple/core/security/session_crypto.dart';
import 'package:sunset_ripple/core/security/session_handshake.dart';
import 'package:sunset_ripple/core/session/room_session.dart';

void main() {
  test(
    'oversized sealed packet is dropped without sending plaintext',
    () async {
      final session = RoomSession(audioIo: MockAudioIo(), selfNickname: 'Host');
      addTearDown(session.dispose);
      session.secureCodec = SecureFrameCodec(
        await SessionCipher.fromKey(Uint8List(32)),
      );
      final sent = <Frame>[];
      session.onSendFrame = sent.add;
      await session.sendFrame(
        Frame(
          type: FrameType.chat,
          senderId: 1,
          seq: 1,
          payload: Uint8List(Frame.maxPayloadSize),
        ),
      );
      expect(sent, isEmpty);
    },
  );

  test(
    'encrypted session rejects plaintext join but accepts a sealed join',
    () async {
      final session = RoomSession(audioIo: MockAudioIo(), selfNickname: 'Host');
      addTearDown(session.dispose);
      await session.createRoom(startAudio: false);
      session.secureCodec = SecureFrameCodec(
        await SessionCipher.fromKey(Uint8List(32)),
      );
      final join = Frame(
        type: FrameType.joinReq,
        senderId: 0,
        seq: 1,
        payload:
            JoinRequestPayload(
              nickname: 'Guest',
              sessionToken: Uint8List(16)..[0] = 1,
            ).encode(),
      );
      await session.handleIncomingFrame(join);
      expect(session.members.length, 1);
      final sender = SecureFrameCodec(
        await SessionCipher.fromKey(Uint8List(32)),
      );
      await session.handleIncomingFrame(await sender.seal(join));
      expect(session.members.length, 2);
    },
  );
}
