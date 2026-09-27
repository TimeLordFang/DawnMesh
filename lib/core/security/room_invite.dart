import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/scrypt.dart';

/// Four digits authenticate room admission; they are never an AES traffic key.
class RoomInvite {
  final String code;
  Future<BigInt>? _scalar;
  RoomInvite._(this.code);

  factory RoomInvite.generate() =>
      RoomInvite._(Random.secure().nextInt(10000).toString().padLeft(4, '0'));

  factory RoomInvite.parse(String input) {
    final code = input.trim();
    if (!RegExp(r'^[0-9]{4}$').hasMatch(code)) {
      throw const FormatException('请输入 4 位数字邀请码。');
    }
    return RoomInvite._(code);
  }

  Future<BigInt> passwordScalar() => _scalar ??= _deriveScalar(code);

  static Future<BigInt> _deriveScalar(String code) => Isolate.run(() {
    final kdf = Scrypt()
      ..init(
        ScryptParameters(
          16384,
          8,
          1,
          40,
          Uint8List.fromList(utf8.encode('DawnMesh SPAKE2 PIN v2')),
        ),
      );
    final bytes = kdf.process(Uint8List.fromList(ascii.encode(code)));
    return bytes.fold<BigInt>(BigInt.zero, (v, b) => (v << 8) | BigInt.from(b));
  });

  @override
  String toString() => 'RoomInvite([redacted])';
}
