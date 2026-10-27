import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as hashes;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../protocol/frame.dart';
import '../protocol/frame_type.dart';
import '../protocol/payloads/join_request.dart';
import 'spake2.dart';

/// Independent signing and key-agreement keys. The private keys are never
/// distributed with the room traffic key. Public keys travel inside PAKE/AEAD.
class MemberIdentity {
  MemberIdentity._(this._signing, this._agreement, this.public);
  final SimpleKeyPair _signing;
  final SimpleKeyPair _agreement;
  final MemberPublicIdentity public;
  static final _ed = Ed25519();
  static final _dh = X25519();

  static Future<MemberIdentity> create() async => fromSeed(
    Uint8List.fromList(await SecretKeyData.random(length: 32).extractBytes()),
  );

  static Future<MemberIdentity> fromSeed(Uint8List seed) async {
    if (seed.length != 32) throw ArgumentError('Member identity seed size');
    final signing = await _ed.newKeyPairFromSeed(
      Spake2Keys.hkdf(seed, 'DawnMesh member signing v1'),
    );
    final agreement = await _dh.newKeyPairFromSeed(
      Spake2Keys.hkdf(seed, 'DawnMesh member agreement v1'),
    );
    return MemberIdentity._(
      signing,
      agreement,
      MemberPublicIdentity(
        Uint8List.fromList((await signing.extractPublicKey()).bytes),
        Uint8List.fromList((await agreement.extractPublicKey()).bytes),
      ),
    );
  }

  static final _loading = <FlutterSecureStorage, Future<MemberIdentity>>{};

  /// A dedicated secret: never derive signing keys from the proof sent to a
  /// server. Concurrent loads share initialization, then release it before
  /// callers resume. Completed futures do not retain an old event-loop zone.
  static Future<MemberIdentity> load({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) async {
    final pending = _loading[storage];
    if (pending != null) return pending;
    final task = _readIdentity(storage);
    _loading[storage] = task;
    try {
      return await task;
    } finally {
      if (identical(_loading[storage], task)) _loading.remove(storage);
    }
  }

  static Future<MemberIdentity> _readIdentity(
    FlutterSecureStorage storage,
  ) async {
    const key = 'member_identity_seed_v1';
    final saved = await storage.read(key: key);
    final seed = saved == null
        ? Uint8List.fromList(
            await SecretKeyData.random(length: 32).extractBytes(),
          )
        : base64Decode(saved);
    if (seed.length != 32) {
      throw const FormatException('Invalid stored member identity');
    }
    if (saved == null) await storage.write(key: key, value: base64Encode(seed));
    return fromSeed(seed);
  }

  Future<List<int>> sign(List<int> bytes) async =>
      (await _ed.sign(bytes, keyPair: _signing)).bytes;

  Future<List<int>> agreementSecret(Uint8List remotePublicKey) async {
    if (remotePublicKey.length != 32) throw ArgumentError('Agreement key size');
    final secret = await _dh.sharedSecretKey(
      keyPair: _agreement,
      remotePublicKey: SimplePublicKey(
        remotePublicKey,
        type: KeyPairType.x25519,
      ),
    );
    return secret.extractBytes();
  }

  Future<Uint8List> wrappingKey(
    MemberPublicIdentity peer,
    Uint8List context,
  ) async {
    final secret = await _dh.sharedSecretKey(
      keyPair: _agreement,
      remotePublicKey: SimplePublicKey(
        peer.agreement,
        type: KeyPairType.x25519,
      ),
    );
    return Spake2Keys.hkdf(
      Uint8List.fromList(await secret.extractBytes()),
      'DawnMesh member key wrapping v3 ${base64Encode(context)}',
    );
  }
}

class MemberPublicIdentity {
  MemberPublicIdentity(this.signing, this.agreement) {
    if (signing.length != 32 || agreement.length != 32) {
      throw ArgumentError('Member public keys must be 32 bytes');
    }
  }
  final Uint8List signing;
  final Uint8List agreement;
  Uint8List get bytes => Uint8List.fromList([...signing, ...agreement]);
  String get id => base64Encode(signing);
  String get messageNamespace =>
      base64UrlEncode(hashes.sha256.convert(bytes).bytes.take(16).toList())
          .replaceAll('=', '');

  /// Full SHA-256 of both public keys; independent of nickname and room IDs.
  String get fingerprint {
    final digest = hashes.sha256.convert(bytes).toString().toUpperCase();
    return [
      for (var i = 0; i < digest.length; i += 4) digest.substring(i, i + 4),
    ].join(' ');
  }

  static MemberPublicIdentity decode(List<int> bytes) {
    if (bytes.length != 64) throw const FormatException('Member identity size');
    return MemberPublicIdentity(
      Uint8List.fromList(bytes.sublist(0, 32)),
      Uint8List.fromList(bytes.sublist(32)),
    );
  }

  Future<bool> verify(List<int> bytes, List<int> signature) => Ed25519().verify(
    bytes,
    signature: Signature(
      signature,
      publicKey: SimplePublicKey(signing, type: KeyPairType.ed25519),
    ),
  );
}

class AuthenticatedMember {
  AuthenticatedMember(this.token, this.identity);
  final Uint8List token;
  final MemberPublicIdentity identity;
}

/// A PAKE-pinned host certifies the current member-id to public-key mapping.
/// This is separate from the user-editable nickname / short device code.
class RoomAuthentication {
  RoomAuthentication({
    required this.self,
    required this.context,
    required this.host,
  });
  final MemberIdentity self;
  final Uint8List context;
  MemberPublicIdentity host;
  final members = <int, AuthenticatedMember>{};
  final _pending = <String, AuthenticatedMember>{};

  void register(Uint8List token, MemberPublicIdentity identity) {
    if (members.isNotEmpty && identity.id == host.id) {
      throw StateError('Host identity cannot be admitted as a guest');
    }
    final conflict = [...members.values, ..._pending.values].any(
      (member) =>
          (Spake2Keys.equal(member.token, token) ||
              member.identity.id == identity.id) &&
          !Spake2Keys.equal(member.identity.bytes, identity.bytes),
    );
    if (conflict) {
      throw StateError('Admission token or member key bundle changed');
    }
    if (_pending.length >= 15) _pending.remove(_pending.keys.first);
    _pending[base64Encode(token)] = AuthenticatedMember(token, identity);
  }

  int? existingMemberId(Uint8List token) {
    final pending = _pending[base64Encode(token)];
    if (pending == null) return null;
    return members.entries
        .where((e) => e.value.identity.id == pending.identity.id)
        .firstOrNull
        ?.key;
  }

  bool bind(int id, Uint8List token) {
    final member =
        _pending.remove(base64Encode(token)) ??
        members.values
            .where((m) => Spake2Keys.equal(m.token, token))
            .firstOrNull;
    if (member == null || id < 1 || id > 16) return false;
    if ((id == 1) != (member.identity.id == host.id)) return false;
    final previous = members[id];
    if (previous != null && previous.identity.id != member.identity.id) {
      return false;
    }
    if (members.entries.any(
      (entry) =>
          entry.key != id && entry.value.identity.id == member.identity.id,
    )) {
      return false;
    }
    members[id] = member;
    return true;
  }

  List<int> _signedBytes(int epoch, List<int> encoded) => [
    ...utf8.encode('DawnMesh authenticated frame v3\u0000'),
    ...context,
    ...epochBytes(epoch),
    ...encoded,
  ];

  static Uint8List epochBytes(int epoch) =>
      (ByteData(4)..setUint32(0, epoch)).buffer.asUint8List();

  Future<Uint8List> sign(Frame frame, int epoch) async {
    final encoded = frame.encode();
    return Uint8List.fromList([
      ...self.public.signing,
      ...await self.sign(_signedBytes(epoch, encoded)),
      ...encoded,
    ]);
  }

  Future<Frame> verify(Uint8List plaintext, int epoch) async {
    if (plaintext.length < 96 + Frame.headerSize) {
      throw const FormatException('Missing member signature');
    }
    final frame = Frame.decode(Uint8List.sublistView(plaintext, 96));
    if (frame == null) throw const FormatException('Invalid signed frame');
    MemberPublicIdentity? identity;
    if (frame.type == FrameType.joinReq && frame.senderId == 0) {
      final join = JoinRequestPayload.decode(frame.payload);
      if (join != null) {
        identity =
            (_pending[base64Encode(join.sessionToken)] ??
                    members.values
                        .where(
                          (m) => Spake2Keys.equal(m.token, join.sessionToken),
                        )
                        .firstOrNull)
                ?.identity;
      }
      // A non-host mesh relay has not observed this peer's PAKE credentials.
      // It may relay a self-signed join, but only the host can bind its PAKE-
      // authenticated token. This cannot authorize ordinary member traffic.
      identity ??= MemberPublicIdentity(
        Uint8List.fromList(plaintext.sublist(0, 32)),
        Uint8List(32),
      );
    } else {
      identity = frame.senderId == 1 ? host : members[frame.senderId]?.identity;
    }
    if (identity == null ||
        !Spake2Keys.equal(identity.signing, plaintext.sublist(0, 32)) ||
        !await identity.verify(
          _signedBytes(epoch, plaintext.sublist(96)),
          plaintext.sublist(32, 96),
        )) {
      throw StateError('Uncertified sender or invalid member signature');
    }
    return frame;
  }

  Uint8List encodeMembers() => Uint8List.fromList([
    1,
    members.length,
    for (final entry in members.entries) ...[
      entry.key,
      ...entry.value.token,
      ...entry.value.identity.bytes,
    ],
  ]);

  /// Invoked only for a host-signed memberKeys control message.
  void acceptMembers(Uint8List data) {
    if (data.length < 2 ||
        data[0] != 1 ||
        data[1] < 1 ||
        data[1] > 16 ||
        data.length != 2 + data[1] * 81) {
      throw const FormatException('Member key roster');
    }
    final next = <int, AuthenticatedMember>{};
    final keys = <String>{};
    for (var i = 2; i < data.length; i += 81) {
      final id = data[i];
      final identity = MemberPublicIdentity.decode(
        data.sublist(i + 17, i + 81),
      );
      if (id < 1 || id > 16 || next.containsKey(id) || !keys.add(identity.id)) {
        throw const FormatException('Duplicate member identity');
      }
      next[id] = AuthenticatedMember(
        Uint8List.fromList(data.sublist(i + 1, i + 17)),
        identity,
      );
    }
    if (next[1]?.identity.id != host.id) {
      throw StateError('Host key replacement');
    }
    members
      ..clear()
      ..addAll(next);
  }

  /// The mapping is derived from an authenticated host handover plan. Pin the
  /// successor before reconnecting; the PAKE response cannot substitute a host.
  void transfer(Map<int, int> oldToNew) {
    final next = <int, AuthenticatedMember>{};
    for (final entry in oldToNew.entries) {
      final member = members[entry.key];
      if (member == null) throw StateError('Uncertified host transfer member');
      next[entry.value] = member;
    }
    final successor = next[1];
    if (successor == null) throw StateError('Missing certified successor');
    host = successor.identity;
    members
      ..clear()
      ..addAll(next);
    _pending.clear();
  }
}
