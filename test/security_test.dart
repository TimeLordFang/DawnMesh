import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:dawn_mesh/core/audio/audio_io.dart';
import 'package:dawn_mesh/core/protocol/frame.dart';
import 'package:dawn_mesh/core/protocol/frame_type.dart';
import 'package:dawn_mesh/core/protocol/payloads/chat_message.dart';
import 'package:dawn_mesh/core/security/session_crypto.dart';
import 'package:dawn_mesh/core/security/session_handshake.dart';
import 'package:dawn_mesh/core/session/room_session.dart';

void main() {
  group('SessionCrypto Tests', () {
    test(
      'SessionCipher roundtrip encryption and decryption with AAD',
      () async {
        final keyBytes = Uint8List(32);
        for (int i = 0; i < 32; i++) {
          keyBytes[i] = i + 1;
        }
        final cipher = await SessionCipher.fromKey(keyBytes);

        final plaintext = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
        final aad = Uint8List.fromList([0xAA, 0xBB]);

        final packet = await cipher.encrypt(plaintext, associatedData: aad);
        expect(packet.nonce.length, SessionCipher.nonceBytes);
        expect(
          packet.ciphertext.length,
          plaintext.length + SessionCipher.tagBytes,
        );

        final decrypted = await cipher.decrypt(packet, associatedData: aad);
        expect(decrypted, equals(plaintext));
      },
    );

    test('SessionCipher rejects corrupted ciphertext or wrong tag', () async {
      final keyBytes = Uint8List(32);
      final cipher = await SessionCipher.fromKey(keyBytes);

      final plaintext = Uint8List.fromList([10, 20, 30]);
      final packet = await cipher.encrypt(plaintext);

      // Tamper ciphertext
      final corruptedCt = Uint8List.fromList(packet.ciphertext);
      corruptedCt[0] ^= 0xFF;
      final corruptedPacket = EncryptedPacket(
        nonce: packet.nonce,
        ciphertext: corruptedCt,
      );

      expect(
        () async => await cipher.decrypt(corruptedPacket),
        throwsA(isA<Exception>()),
      );
    });

    test('SessionCipher rejects replayed nonces', () async {
      final keyBytes = Uint8List(32);
      final cipher = await SessionCipher.fromKey(keyBytes);

      final plaintext = Uint8List.fromList([1, 2, 3]);
      final packet = await cipher.encrypt(plaintext);

      final dec1 = await cipher.decrypt(packet);
      expect(dec1, equals(plaintext));

      // Second decryption of the same packet with identical nonce must throw StateError
      expect(() async => await cipher.decrypt(packet), throwsStateError);
    });
  });

  group('SecureFrameCodec Tests', () {
    test(
      'SecureFrameCodec rejects already sealed frame or mismatched header',
      () async {
        final keyBytes = Uint8List(32);
        final cipher = await SessionCipher.fromKey(keyBytes);
        final codec = SecureFrameCodec(cipher);

        final frame = Frame(
          type: FrameType.sealed,
          senderId: 1,
          seq: 1,
          payload: Uint8List(30),
        );

        expect(() async => await codec.seal(frame), throwsArgumentError);
      },
    );

    test('RoomSession chat sealing pipeline: unsealed by default, sealed when secureCodec is set', () async {
      final sent = <Frame>[];
      final session = RoomSession(
        audioIo: MockAudioIo(),
        selfNickname: '加密测试者',
      );
      session.onSendFrame = sent.add;
      await session.createRoom();

      // 1. Default production state (secureCodec == null): sends plain FrameType.chat
      expect(session.secureCodec, isNull);
      await session.sendChat('明文兼容消息');
      expect(sent.last.type, FrameType.chat);

      // 2. When secureCodec is configured: automatically seals to FrameType.sealed
      final keyBytes = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        keyBytes[i] = i + 1;
      }
      final cipher = await SessionCipher.fromKey(keyBytes);
      final codec = SecureFrameCodec(cipher);
      session.secureCodec = codec;

      await session.sendChat('机密聊天消息');
      final sealedFrame = sent.last;
      expect(sealedFrame.type, FrameType.sealed);

      // 3. Opening the sealed frame restores the original FrameType.chat and text
      final openedFrame = await codec.open(sealedFrame);
      expect(openedFrame.type, FrameType.chat);
      expect(openedFrame.senderId, session.selfMemberId);

      final payload = ChatMessagePayload.decode(openedFrame.payload);
      expect(payload, isNotNull);
      expect(payload!.text, '机密聊天消息');

      await session.dispose();
    });
  });
}
