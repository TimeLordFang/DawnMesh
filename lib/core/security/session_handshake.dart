import 'dart:typed_data';

import '../protocol/frame.dart';
import '../protocol/frame_type.dart';
import 'session_crypto.dart';

/// 安全信封编解码器：将普通 [Frame] 密封打包为 [FrameType.sealed] 帧，或反向解封。
class SecureFrameCodec {
  static const int nonceBytes = 12;
  static const int tagBytes = 16;
  static const int protocolVersion = 1;

  /// 内层明文载荷上限（外层 512 字节减去 6 字节帧头与 28 字节 Nonce+Tag）。
  static const int maxPlaintextPayload =
      Frame.maxPayloadSize - Frame.headerSize - nonceBytes - tagBytes;

  final SessionCipher cipher;

  SecureFrameCodec(this.cipher);

  /// 将明文帧包装密封为 SEALED 帧。
  Future<Frame> seal(Frame frame) async {
    if (frame.type == FrameType.sealed) {
      throw ArgumentError('frame is already sealed');
    }

    final encoded = frame.encode();
    final aad = _associatedData(frame.senderId, frame.seq);
    final packet = await cipher.encrypt(encoded, associatedData: aad);

    final payload = Uint8List(packet.nonce.length + packet.ciphertext.length);
    payload.setRange(0, packet.nonce.length, packet.nonce);
    payload.setRange(packet.nonce.length, payload.length, packet.ciphertext);

    if (payload.length > Frame.maxPayloadSize) {
      throw StateError('sealed frame exceeds transport limit');
    }

    return Frame(
      type: FrameType.sealed,
      senderId: frame.senderId,
      seq: frame.seq,
      payload: payload,
    );
  }

  /// 解封 SEALED 帧还原出明文帧。
  Future<Frame> open(Frame frame) async {
    if (frame.type != FrameType.sealed) {
      throw ArgumentError('sealed frame required');
    }
    if (frame.payload.length < nonceBytes + tagBytes) {
      throw ArgumentError('sealed frame is truncated');
    }

    final nonce = Uint8List.sublistView(frame.payload, 0, nonceBytes);
    final ciphertext = Uint8List.sublistView(frame.payload, nonceBytes);
    final aad = _associatedData(frame.senderId, frame.seq);

    final packet = EncryptedPacket(nonce: nonce, ciphertext: ciphertext);
    final plaintext = await cipher.decrypt(packet, associatedData: aad);

    final decoded = Frame.decode(plaintext);
    if (decoded == null) {
      throw const FormatException('failed to decode decrypted frame');
    }
    if (decoded.senderId != frame.senderId || decoded.seq != frame.seq) {
      throw StateError('sealed frame header mismatch');
    }

    return decoded;
  }

  static Uint8List _associatedData(int senderId, int sequence) {
    final buffer = Uint8List(5);
    final byteData = ByteData.sublistView(buffer);
    byteData.setUint8(0, FrameType.sealed.value);
    byteData.setUint8(1, senderId);
    byteData.setUint16(2, sequence, Endian.big);
    byteData.setUint8(4, protocolVersion);
    return buffer;
  }
}
