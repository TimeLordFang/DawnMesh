import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'session_crypto.dart';
import 'session_handshake.dart';

/// A fresh 128-bit bearer secret for a trusted group, never advertised or logged.
/// Possession authorizes membership; this does not identify individual humans.
class RoomInvite {
  final String code;
  RoomInvite._(this.code);

  factory RoomInvite.generate() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return RoomInvite._(base64Url.encode(bytes).replaceAll('=', ''));
  }

  factory RoomInvite.parse(String input) {
    final code = input.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(code)) {
      throw const FormatException('邀请码应为 22 位，请完整复制房主的邀请码。');
    }
    final bytes = base64Url.decode('$code==');
    if (bytes.length != 16 ||
        base64Url.encode(bytes).replaceAll('=', '') != code) {
      throw const FormatException('邀请码格式不正确。');
    }
    return RoomInvite._(code);
  }

  Future<SecureFrameCodec> createCodec() async {
    // The input is uniform random entropy, NOT a human password. Domain-separated
    // SHA-256 expands it to an AES key without introducing a weak password KDF.
    final bytes = base64Url.decode('$code==');
    final key = Uint8List.fromList(
      crypto.sha256.convert([
        ...utf8.encode('DawnMesh room key v1\u0000'),
        ...bytes,
      ]).bytes,
    );
    return SecureFrameCodec(await SessionCipher.fromKey(key));
  }

  @override
  String toString() => 'RoomInvite([redacted])';
}
