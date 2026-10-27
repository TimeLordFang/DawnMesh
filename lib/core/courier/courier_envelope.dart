import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';

import '../security/member_identity.dart';
import '../security/spake2.dart';

/// Independently signed recipient-only ciphertext. Room hosts and carriers
/// cannot decrypt it. Mutable transport budgets are deliberately not authority.
class CourierEnvelope {
  CourierEnvelope._(this.wire);
  static const headerSize = 194;
  static const maxTextBytes = 1024;
  static const maxWireBytes = headerSize + 12 + maxTextBytes + 16 + 64;
  static const lifetime = Duration(hours: 24);
  final Uint8List wire;
  bool get revoked => wire[1] == 1;
  Uint8List get id => Uint8List.sublistView(wire, 2, 18);
  int get createdMs => ByteData.sublistView(wire).getUint64(18);
  int get expiresMs => ByteData.sublistView(wire).getUint64(26);
  MemberPublicIdentity get author =>
      MemberPublicIdentity.decode(wire.sublist(34, 98));
  MemberPublicIdentity get recipient =>
      MemberPublicIdentity.decode(wire.sublist(98, 162));
  String get key => '${author.id}:${base64Encode(id)}';
  String get digest => hash.sha256.convert(wire).toString().substring(0, 32);

  static Future<CourierEnvelope> create({
    required MemberIdentity author,
    required MemberPublicIdentity recipient,
    required String text,
    DateTime? now,
  }) async {
    final bytes = utf8.encode(text.trim());
    if (bytes.isEmpty || bytes.length > maxTextBytes) {
      throw ArgumentError('Message must be 1–1024 UTF-8 bytes');
    }
    final time = now ?? DateTime.now();
    final dh = X25519();
    final ephemeral = await dh.newKeyPair();
    final header = Uint8List(headerSize);
    header[0] = 1;
    header.setRange(
      2,
      18,
      List.generate(16, (_) => Random.secure().nextInt(256)),
    );
    ByteData.sublistView(header)
      ..setUint64(18, time.millisecondsSinceEpoch)
      ..setUint64(26, time.add(lifetime).millisecondsSinceEpoch);
    header.setRange(34, 98, author.public.bytes);
    header.setRange(98, 162, recipient.bytes);
    header.setRange(162, 194, (await ephemeral.extractPublicKey()).bytes);
    final secret = await dh.sharedSecretKey(
      keyPair: ephemeral,
      remotePublicKey: SimplePublicKey(
        recipient.agreement,
        type: KeyPairType.x25519,
      ),
    );
    final key = _derive(await secret.extractBytes(), header);
    final aes = AesGcm.with256bits();
    final box = await aes.encrypt(
      bytes,
      secretKey: SecretKey(key),
      aad: header,
    );
    final signed = [
      ...header,
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ];
    return CourierEnvelope._(
      Uint8List.fromList([...signed, ...await author.sign(signed)]),
    );
  }

  static Uint8List _derive(List<int> secret, List<int> header) =>
      Spake2Keys.hkdf(
        Uint8List.fromList(secret),
        'DawnMesh courier v1 ${base64Encode(header)}',
      );

  Future<CourierEnvelope> revoke(MemberIdentity identity) async {
    if (author.id != identity.public.id) {
      throw StateError('Only the author can revoke');
    }
    final header = Uint8List.fromList(wire.take(headerSize).toList())..[1] = 1;
    return CourierEnvelope._(
      Uint8List.fromList([...header, ...await identity.sign(header)]),
    );
  }

  static Future<CourierEnvelope?> verify(Uint8List input, DateTime now) async {
    if (input.length < headerSize + 64 ||
        input.length > maxWireBytes ||
        input[0] != 1 ||
        input[1] > 1) {
      return null;
    }
    final envelope = CourierEnvelope._(Uint8List.fromList(input));
    if ((envelope.revoked && input.length != headerSize + 64) ||
        (!envelope.revoked && input.length < headerSize + 12 + 1 + 16 + 64)) {
      return null;
    }
    final current = now.millisecondsSinceEpoch;
    if (envelope.expiresMs <= current ||
        envelope.createdMs > current + 300000 ||
        envelope.expiresMs <= envelope.createdMs ||
        envelope.expiresMs - envelope.createdMs > lifetime.inMilliseconds) {
      return null;
    }
    if (!await envelope.author.verify(
      input.sublist(0, input.length - 64),
      input.sublist(input.length - 64),
    )) {
      return null;
    }
    return envelope;
  }

  Future<String> decrypt(MemberIdentity identity) async {
    if (revoked ||
        recipient.id != identity.public.id ||
        !Spake2Keys.equal(recipient.bytes, identity.public.bytes)) {
      throw StateError('Not the recipient');
    }
    final header = Uint8List.sublistView(wire, 0, headerSize);
    final secret = await identity.agreementSecret(
      Uint8List.sublistView(wire, 162, 194),
    );
    final bodyEnd = wire.length - 64;
    final plain = await AesGcm.with256bits().decrypt(
      SecretBox(
        wire.sublist(headerSize + 12, bodyEnd - 16),
        nonce: wire.sublist(headerSize, headerSize + 12),
        mac: Mac(wire.sublist(bodyEnd - 16, bodyEnd)),
      ),
      secretKey: SecretKey(_derive(secret, header)),
      aad: header,
    );
    return utf8.decode(plain);
  }
}
