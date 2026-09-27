import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/scrypt.dart';

import '../security/room_invite.dart';
import '../security/session_crypto.dart';

/// Separate server admission and key-wrapping secrets, scoped by a random salt.
class InternetInviteCredentials {
  InternetInviteCredentials._(this.salt, this._bytes);
  final String salt;
  final Uint8List _bytes;
  String get credential => base64Encode(_bytes.sublist(0, 32));
  Uint8List get _aad => Uint8List.fromList([
    ...utf8.encode('DawnMesh internet invite v2'),
    ...base64Decode(salt),
  ]);

  static String randomSalt() {
    final random = Random.secure();
    return base64Encode(List.generate(16, (_) => random.nextInt(256)));
  }

  static Future<InternetInviteCredentials> derive(
    RoomInvite invite,
    String salt,
  ) async {
    if (salt.isEmpty) throw const FormatException('请升级服务端并重新创建房间');
    final rawSalt = base64Decode(salt);
    if (rawSalt.length != 16) throw const FormatException('房间验证参数无效');
    final code = invite.code;
    final bytes = await Isolate.run(() {
      final kdf = Scrypt()
        ..init(
          ScryptParameters(
            16384,
            8,
            1,
            64,
            Uint8List.fromList([
              ...utf8.encode('DawnMesh internet invite v2'),
              ...rawSalt,
            ]),
          ),
        );
      return kdf.process(Uint8List.fromList(ascii.encode(code)));
    });
    return InternetInviteCredentials._(salt, bytes);
  }

  Future<String> wrap(Uint8List roomKey) async {
    if (roomKey.length != 32) throw const FormatException('房间密钥无效');
    final cipher = await SessionCipher.fromKey(
      Uint8List.sublistView(_bytes, 32),
    );
    final packet = await cipher.encrypt(roomKey, associatedData: _aad);
    return base64Encode([...packet.nonce, ...packet.ciphertext]);
  }

  Future<Uint8List> unwrap(String encoded) async {
    final packet = base64Decode(encoded);
    if (packet.length != 60) throw const FormatException('房间密钥无效');
    final cipher = await SessionCipher.fromKey(
      Uint8List.sublistView(_bytes, 32),
    );
    return Uint8List.fromList(
      await cipher.decrypt(
        EncryptedPacket(
          nonce: Uint8List.sublistView(packet, 0, 12),
          ciphertext: Uint8List.sublistView(packet, 12),
        ),
        associatedData: _aad,
      ),
    );
  }
}
