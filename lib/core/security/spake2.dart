import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/prime256v1.dart';

/// RFC 9382 P256-SHA256-HKDF-HMAC, uncompressed SEC1 wire points.
/// Protocol wrapper supplies explicit, session-bound A/B identities.
/// PointyCastle arithmetic is not certified constant-time: see SECURITY_REVIEW.
class Spake2 {
  static final domain = ECCurve_prime256v1();
  static final _m =
      domain.curve.decodePoint(
        hexBytes(
          '02886e2f97ace46e55ba9dd7242579f2993b64e16ef3dcab95afd497333d8fa12f',
        ),
      )!;
  static final _n =
      domain.curve.decodePoint(
        hexBytes(
          '03d8bbd6c639c62937b04d997f38c3770719c629d7014d49a24b4f98baa1292b49',
        ),
      )!;
  final bool isA;
  final BigInt _w;
  final BigInt _secret;
  late final Uint8List message =
      ((domain.G * _secret)! + ((isA ? _m : _n) * _w)!)!.getEncoded(false);
  bool _used = false;

  Spake2({
    required this.isA,
    required BigInt passwordScalar,
    BigInt? testSecret,
  }) : _w = passwordScalar % domain.n,
       _secret = testSecret ?? _randomScalar();

  static BigInt _randomScalar() {
    final random = Random.secure();
    while (true) {
      final scalar = List.generate(
        32,
        (_) => random.nextInt(256),
      ).fold(BigInt.zero, (v, b) => (v << 8) | BigInt.from(b));
      if (scalar > BigInt.zero && scalar < domain.n) return scalar;
    }
  }

  Spake2Keys finish(
    Uint8List peer, {
    required Uint8List a,
    required Uint8List b,
  }) {
    if (_used) throw StateError('PAKE ephemeral must not be reused');
    _used = true;
    final point = _decode(peer);
    final unmasked = point - ((isA ? _n : _m) * _w)!;
    if (unmasked == null || unmasked.isInfinity) {
      throw const FormatException('invalid PAKE point');
    }
    final shared = unmasked * _secret;
    if (shared == null || shared.isInfinity) {
      throw const FormatException('invalid PAKE secret');
    }
    final transcript = BytesBuilder();
    for (final field in [
      a,
      b,
      isA ? message : peer,
      isA ? peer : message,
      shared.getEncoded(false),
      scalarBytes(_w),
    ]) {
      final size = Uint8List(8);
      ByteData.sublistView(size).setUint64(0, field.length, Endian.little);
      transcript
        ..add(size)
        ..add(field);
    }
    return Spake2Keys(transcript.takeBytes());
  }

  static ECPoint _decode(Uint8List encoded) {
    if (encoded.length != 65 || encoded[0] != 4) {
      throw const FormatException('invalid SEC1 point');
    }
    // Do not rely on decodePoint accepting/rejecting off-curve coordinates.
    final prime = BigInt.parse(
      'ffffffff00000001000000000000000000000000ffffffffffffffffffffffff',
      radix: 16,
    );
    BigInt number(List<int> b) =>
        b.fold(BigInt.zero, (v, n) => (v << 8) | BigInt.from(n));
    final x = number(encoded.sublist(1, 33));
    final y = number(encoded.sublist(33));
    final aa = domain.curve.a!.toBigInteger()!;
    final bb = domain.curve.b!.toBigInteger()!;
    if (x >= prime ||
        y >= prime ||
        (y * y - x * x * x - aa * x - bb) % prime != BigInt.zero) {
      throw const FormatException('point is not on P-256');
    }
    return domain.curve.decodePoint(encoded)!; // P-256 has cofactor 1.
  }

  static Uint8List scalarBytes(BigInt value) =>
      hexBytes(value.toRadixString(16).padLeft(64, '0'));
  static Uint8List hexBytes(String value) => Uint8List.fromList([
    for (var i = 0; i < value.length; i += 2)
      int.parse(value.substring(i, i + 2), radix: 16),
  ]);
}

class Spake2Keys {
  final Uint8List transcript;
  late final List<int> digest = crypto.sha256.convert(transcript).bytes;
  late final Uint8List sharedKey = Uint8List.fromList(digest.sublist(0, 16));
  late final Uint8List _confirmKeys = hkdf(
    digest.sublist(16),
    'ConfirmationKeys',
  );
  late final Uint8List confirmA = Uint8List.fromList(
    crypto.Hmac(
      crypto.sha256,
      _confirmKeys.sublist(0, 16),
    ).convert(transcript).bytes,
  );
  late final Uint8List confirmB = Uint8List.fromList(
    crypto.Hmac(
      crypto.sha256,
      _confirmKeys.sublist(16),
    ).convert(transcript).bytes,
  );
  Spake2Keys(this.transcript);

  static Uint8List hkdf(List<int> key, String info) {
    final prk = crypto.Hmac(crypto.sha256, Uint8List(32)).convert(key).bytes;
    return Uint8List.fromList(
      crypto.Hmac(crypto.sha256, prk).convert([...utf8.encode(info), 1]).bytes,
    );
  }

  static bool equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}
