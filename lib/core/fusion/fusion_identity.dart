import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';

import '../session/member.dart';
import '../protocol/room_limits.dart';
import '../protocol/bounded_utf8.dart';

/// The room's public key is its identity. Only its creator signs membership;
/// every admitted phone can carry that signed state to a server.
class FusionIdentity {
  FusionIdentity._(
    this.publicKey,
    this.secret,
    this.name,
    this.signature, [
    this._keyPair,
  ]);

  final Uint8List publicKey;
  final Uint8List secret;
  final String name;
  final Uint8List signature;
  final SimpleKeyPair? _keyPair;
  static final _algorithm = Ed25519();
  static const maxStateBytes = 74 + RoomLimits.fusionMembers * (18 + 40);
  String get roomId => base64Url.encode(publicKey).replaceAll('=', '');
  String get relayToken => base64Encode(secret);
  bool get canSign => _keyPair != null;

  static Future<FusionIdentity> create(String name) async {
    final pair = await _algorithm.newKeyPair();
    final public = Uint8List.fromList((await pair.extractPublicKey()).bytes);
    final secret = Uint8List.fromList(
      (await SecretKeyData.random(length: 32).extractBytes()),
    );
    final text = boundedUtf8(name, 64);
    final body = [
      1,
      ...public,
      ...hashes.sha256.convert(secret).bytes,
      ...text,
    ];
    final signature = await _algorithm.sign(body, keyPair: pair);
    return FusionIdentity._(
      public,
      secret,
      utf8.decode(text),
      Uint8List.fromList(signature.bytes),
      pair,
    );
  }

  Uint8List get manifest => Uint8List.fromList([
    1,
    ...publicKey,
    ...hashes.sha256.convert(secret).bytes,
    ...utf8.encode(name),
    ...signature,
  ]);

  /// Sent only inside the PAKE-established encrypted room channel.
  Uint8List get bootstrap => Uint8List.fromList([
    1,
    ...publicKey,
    ...secret,
    ...utf8.encode(name),
    ...signature,
  ]);

  static Future<FusionIdentity?> openBootstrap(
    List<int> bytes,
    String expectedRoom,
  ) async {
    if (bytes.length < 129 || bytes.length > 193 || bytes[0] != 1) return null;
    try {
      final identity = FusionIdentity._(
        Uint8List.fromList(bytes.sublist(1, 33)),
        Uint8List.fromList(bytes.sublist(33, 65)),
        utf8.decode(bytes.sublist(65, bytes.length - 64)),
        Uint8List.fromList(bytes.sublist(bytes.length - 64)),
      );
      if (identity.roomId != expectedRoom) return null;
      final manifest = identity.manifest;
      if (!await _algorithm.verify(
        manifest.sublist(0, manifest.length - 64),
        signature: Signature(
          identity.signature,
          publicKey: SimplePublicKey(
            identity.publicKey,
            type: KeyPairType.ed25519,
          ),
        ),
      )) {
        return null;
      }
      return identity;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> signState(
    List<Member> members,
    int revision, {
    bool ended = false,
  }) async {
    if (_keyPair == null || members.length > RoomLimits.fusionMembers) {
      throw StateError('Invalid room signer');
    }
    final header = ByteData(10)
      ..setUint64(0, revision)
      ..setUint8(8, ended ? 1 : 0)
      ..setUint8(9, members.length);
    final body = <int>[...header.buffer.asUint8List()];
    for (final member in members) {
      final name = boundedUtf8(member.nickname, 40);
      // A room-scoped pseudonym, never the installation proof or admission token.
      final id = hashes.sha256
          .convert(member.sessionToken ?? [member.memberId])
          .bytes
          .take(16);
      body.addAll([member.memberId, ...id, name.length, ...name]);
    }
    final signature = await _algorithm.sign([
      2,
      ...publicKey,
      ...body,
    ], keyPair: _keyPair);
    return Uint8List.fromList([...body, ...signature.bytes]);
  }

  Future<bool> verifyState(Uint8List state) async {
    if (state.length < 74 ||
        state.length > maxStateBytes ||
        state[8] > 1 ||
        state[9] > RoomLimits.fusionMembers) {
      return false;
    }
    var offset = 10;
    final ids = <int>{};
    for (var i = 0; i < state[9]; i++) {
      if (offset + 18 > state.length - 64) return false;
      if (state[offset] < 1 ||
          state[offset] > RoomLimits.fusionMembers ||
          !ids.add(state[offset])) {
        return false;
      }
      final length = state[offset + 17];
      if (length > 40) return false;
      offset += 18 + length;
    }
    if (offset != state.length - 64) return false;
    return _algorithm.verify(
      [2, ...publicKey, ...state.sublist(0, offset)],
      signature: Signature(
        state.sublist(offset),
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
  }

  static Uint8List memberToken(String installationProof, String roomId) =>
      Uint8List.fromList(
        hashes.Hmac(hashes.sha256, base64Decode(installationProof))
            .convert(utf8.encode('DawnMesh-fusion-member-v1:$roomId'))
            .bytes
            .take(16)
            .toList(),
      );
}
