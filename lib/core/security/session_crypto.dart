import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypt;

/// 密文数据包：12 字节 Nonce + 密文 (含 16 字节 Auth Tag)。
class EncryptedPacket {
  final Uint8List nonce;
  final Uint8List ciphertext;

  EncryptedPacket({required this.nonce, required this.ciphertext});
}

/// 基于 AES-256-GCM 的会话加密器。
///
/// 具备 12 字节 Nonce、128 位认证标签、每发送端 1024 帧滑动防重放窗口。
class SessionCipher {
  static const int nonceBytes = 12;
  static const int tagBits = 128;
  static const int tagBytes = 16;
  static const int replayWindowSize = 1024;
  static const int maxSenderPrefixes = 128;

  final crypt.SecretKey _secretKey;
  final crypt.AesGcm _aesGcm = crypt.AesGcm.with256bits(
    nonceLength: nonceBytes,
  );
  final Map<String, _ReplayWindow> _replayWindows = {};
  final Uint8List _noncePrefix = Uint8List.fromList(
    List.generate(8, (_) => Random.secure().nextInt(256)),
  );
  int _nonceCounter = 0;

  SessionCipher._(this._secretKey);

  /// 直接从 32 字节原始密钥构造加密器。
  static Future<SessionCipher> fromKey(Uint8List keyBytes) async {
    if (keyBytes.length != 32) {
      throw ArgumentError('AES-256 key required (must be 32 bytes)');
    }
    final secretKey = crypt.SecretKeyData(keyBytes);
    return SessionCipher._(secretKey);
  }

  /// 加密明文，附加关联数据 AAD。
  Future<EncryptedPacket> encrypt(
    Uint8List plaintext, {
    Uint8List? associatedData,
  }) async {
    final nonce = Uint8List(nonceBytes);
    if (_nonceCounter > 0xffffffff) throw StateError('room key exhausted');
    nonce.setRange(0, 8, _noncePrefix);
    ByteData.sublistView(nonce).setUint32(8, _nonceCounter++, Endian.big);

    final secretBox = await _aesGcm.encrypt(
      plaintext,
      secretKey: _secretKey,
      nonce: nonce,
      aad: associatedData ?? Uint8List(0),
    );

    // secretBox.cipherText + secretBox.mac.bytes (16 bytes tag)
    final ciphertext = Uint8List(
      secretBox.cipherText.length + secretBox.mac.bytes.length,
    );
    ciphertext.setRange(0, secretBox.cipherText.length, secretBox.cipherText);
    ciphertext.setRange(
      secretBox.cipherText.length,
      ciphertext.length,
      secretBox.mac.bytes,
    );

    return EncryptedPacket(nonce: nonce, ciphertext: ciphertext);
  }

  /// 解密密文并校验防重放及认证标签。
  Future<Uint8List> decrypt(
    EncryptedPacket packet, {
    Uint8List? associatedData,
  }) async {
    if (packet.nonce.length != nonceBytes) throw ArgumentError('invalid nonce');
    final prefix = base64.encode(packet.nonce.sublist(0, 8));
    final counter = ByteData.sublistView(packet.nonce).getUint32(8, Endian.big);
    if (_replayWindows[prefix]?.rejects(counter) ?? false) {
      throw StateError('replayed encrypted frame');
    }

    if (packet.ciphertext.length < tagBytes) {
      throw ArgumentError('ciphertext is shorter than authentication tag');
    }

    final ctLen = packet.ciphertext.length - tagBytes;
    final cipherTextOnly = packet.ciphertext.sublist(0, ctLen);
    final macBytes = packet.ciphertext.sublist(ctLen);

    try {
      final secretBox = crypt.SecretBox(
        cipherTextOnly,
        nonce: packet.nonce,
        mac: crypt.Mac(macBytes),
      );

      final decrypted = await _aesGcm.decrypt(
        secretBox,
        secretKey: _secretKey,
        aad: associatedData ?? Uint8List(0),
      );

      // Mutate replay state only after authentication. Never evict a sender:
      // evicting it would make old captured packets acceptable again.
      if (!_replayWindows.containsKey(prefix) &&
          _replayWindows.length >= maxSenderPrefixes) {
        throw StateError('too many sender sessions; create a new room');
      }
      final window = _replayWindows.putIfAbsent(prefix, _ReplayWindow.new);
      window.accept(counter); // Recheck after await for concurrent duplicates.
      return Uint8List.fromList(decrypted);
    } catch (_) {
      rethrow;
    }
  }
}

/// Records a bounded window without ever accepting counters older than it.
class _ReplayWindow {
  int highest = -1;
  BigInt bits = BigInt.zero;
  static final mask =
      (BigInt.one << SessionCipher.replayWindowSize) - BigInt.one;

  bool rejects(int counter) {
    if (counter > highest) return false;
    final delta = highest - counter;
    return delta >= SessionCipher.replayWindowSize ||
        (bits & (BigInt.one << delta)) != BigInt.zero;
  }

  void accept(int counter) {
    if (rejects(counter)) throw StateError('replayed encrypted frame');
    if (counter > highest) {
      final shift = counter - highest;
      bits = shift >= SessionCipher.replayWindowSize
          ? BigInt.one
          : ((bits << shift) | BigInt.one) & mask;
      highest = counter;
    } else {
      bits |= BigInt.one << (highest - counter);
    }
  }
}
