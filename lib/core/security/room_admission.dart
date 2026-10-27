import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../protocol/frame.dart';
import '../protocol/frame_type.dart';
import '../protocol/relay_budget.dart';
import 'session_crypto.dart';
import 'member_identity.dart';
import 'session_handshake.dart';
import 'spake2.dart';

/// Broadcast-safe PAKE admission. Only an authenticated PAKE peer receives the
/// room's independent random traffic key. No PIN verifier is put on the wire.
class RoomAdmission {
  final BigInt passwordScalar;
  final Uint8List token;
  final int maxPending;
  final MemberIdentity? identity;
  int get _version => identity == null ? 2 : 3;
  RoomAuthentication? _authentication;
  RoomAuthentication? get authentication => _authentication;
  int _epoch = 0;
  final _keyGrants = <int, (Frame, int)>{};
  Future<void> _rotation = Future.value();
  final void Function(Frame) send;
  final Future<void> Function(SecureFrameCodec) onReady;
  bool _host = false;
  bool _closed = false;
  bool _ready = false;
  Uint8List? _trafficKey;
  SecureFrameCodec? _trafficCodec;
  Spake2? _client;
  Uint8List? _attemptToken;
  Spake2Keys? _clientKeys;
  final Map<String, _Pending> _pending = {};
  final List<DateTime> _attempts = [];
  int _totalAttempts = 0;
  int _wireSequence = 0;
  Frame? _outboundHandshake;
  int _handshakeRetries = 0;
  final _completed = <String, _CompletedAdmission>{};

  RoomAdmission({
    required this.passwordScalar,
    required this.token,
    this.maxPending = 5,
    this.identity,
    required this.send,
    required this.onReady,
  }) : assert(maxPending > 0 && maxPending <= 15);

  Future<void> startHost() async {
    _host = true;
    final random = Random.secure();
    _trafficKey = Uint8List.fromList(
      List.generate(32, (_) => random.nextInt(256)),
    );
    if (identity != null) {
      _epoch = 1;
      _authentication = RoomAuthentication(
        self: identity!,
        context: Uint8List.fromList(
          List.generate(16, (_) => random.nextInt(256)),
        ),
        host: identity!.public,
      );
      _authentication!.register(token, identity!.public);
      _authentication!.bind(1, token);
    }
    _trafficCodec = await _codec(_trafficKey!);
    await onReady(_trafficCodec!);
  }

  void startClient({bool freshAttempt = false}) {
    // Room membership keeps its stable installation identity. A new network
    // admission attempt needs a separate challenge ID so an abandoned PAKE on
    // the old route cannot block or complete the new attempt.
    _attemptToken = freshAttempt
        ? Uint8List.fromList(
            List.generate(16, (_) => Random.secure().nextInt(256)),
          )
        : token;
    _ready = false;
    _clientKeys = null;
    _client = Spake2(isA: true, passwordScalar: passwordScalar);
    _emit(1, _attemptToken!, _client!.message);
  }

  int _nextWireSequence() =>
      (identity == null ? 0 : RelayBudget.maximum << 8) |
      (_wireSequence++ & 255);

  Frame? _emit(int kind, Uint8List id, List<int> body) {
    if (_closed) return null;
    final frame = Frame(
      type: kind <= 2 ? FrameType.handshakeHello : FrameType.handshakeConfirm,
      senderId: _host ? 1 : 0,
      seq: _nextWireSequence(),
      payload: Uint8List.fromList([_version, kind, ...id, ...body]),
    );
    if (!_host && (kind == 1 || kind == 3)) {
      _outboundHandshake = frame;
      _handshakeRetries = 0;
    }
    send(frame);
    return frame;
  }

  void _resend(Frame frame) => send(
    Frame(
      type: frame.type,
      senderId: frame.senderId,
      seq: _nextWireSequence(),
      payload: frame.payload,
    ),
  );

  /// Called by the existing two-second heartbeat. Retransmit the same PAKE
  /// transcript, with a fresh transport id, without creating another guess.
  void retryPendingHandshake() {
    final frame = _outboundHandshake;
    if (_closed || _host || _ready || frame == null || _handshakeRetries >= 5) {
      return;
    }
    _handshakeRetries++;
    _resend(frame);
  }

  (Uint8List, Uint8List) _identities(Uint8List id) => (
    Uint8List.fromList([
      ...utf8.encode('DawnMesh PIN v$_version client\u0000'),
      ...id,
    ]),
    Uint8List.fromList(utf8.encode('DawnMesh PIN v$_version host')),
  );

  Future<void> handle(Frame frame) async {
    if (_closed) return;
    final p = frame.payload;
    if (p.length < 18 || p[0] != _version) return;
    final kind = p[1];
    if (frame.type !=
        (kind <= 2 ? FrameType.handshakeHello : FrameType.handshakeConfirm)) {
      return;
    }
    final id = Uint8List.fromList(p.sublist(2, 18));
    final body = Uint8List.fromList(p.sublist(18));
    if (kind == 5 && !_host && identity != null) {
      await _acceptKeyGrant(id, body);
      return;
    }
    if (!_host && _ready) return;
    final index = base64.encode(id);
    final (a, b) = _identities(id);
    if (_host) {
      if (frame.senderId != 0) return;
      final now = DateTime.now();
      _completed.removeWhere(
        (_, item) => now.difference(item.created).inSeconds >= 30,
      );
      final transcript = base64Encode(p);
      final completed = _completed[transcript];
      if (kind == 3 && completed != null) {
        _resend(completed.response);
        return;
      }
      _pending.removeWhere(
        (_, pending) => now.difference(pending.created).inSeconds >= 12,
      );
      if (kind == 1 && body.length == 65) {
        if (_completed.values.any((item) => item.hello == transcript)) return;
        final pending = _pending[index];
        if (pending != null) {
          if (pending.hello == transcript) _emit(2, id, pending.challenge);
          return;
        }
        _attempts.removeWhere((time) => now.difference(time).inSeconds >= 60);
        if (_pending.length >= maxPending ||
            _attempts.length >= max(10, maxPending * 2) ||
            _totalAttempts >= 120) {
          return;
        }
        _attempts.add(now);
        _totalAttempts++;
        final server = Spake2(isA: false, passwordScalar: passwordScalar);
        final keys = server.finish(body, a: a, b: b);
        final challenge = Uint8List.fromList([
          ...server.message,
          ...keys.confirmB,
        ]);
        _pending[index] = _Pending(keys, now, transcript, challenge);
        _emit(2, id, challenge);
      } else if (kind == 3 && body.length == (identity == null ? 32 : 204)) {
        final pending = _pending.remove(
          index,
        ); // A confirmation gets one attempt.
        if (pending == null ||
            !Spake2Keys.equal(body.sublist(0, 32), pending.keys.confirmA)) {
          return;
        }
        // Successful authentication is not a password guess. Retain the
        // lifetime budget for failed/abandoned attempts, including new tokens.
        _totalAttempts--;
        final cipher = await _wrapCipher(pending.keys);
        if (identity != null) {
          final credentials = await cipher.decrypt(
            EncryptedPacket(
              nonce: Uint8List.sublistView(body, 32, 44),
              ciphertext: Uint8List.sublistView(body, 44),
            ),
            associatedData: id,
          );
          if (credentials.length != 144) return;
          final member = MemberPublicIdentity.decode(
            credentials.sublist(16, 80),
          );
          final claims = Uint8List.sublistView(credentials, 0, 80);
          if (!await member.verify(
            _identityProof('member', id, pending.keys, claims),
            credentials.sublist(80),
          )) {
            return;
          }
          _authentication!.register(
            Uint8List.sublistView(credentials, 0, 16),
            member,
          );
        }
        final grantEpoch = _epoch;
        final grant = identity == null
            ? _trafficKey!
            : Uint8List.fromList([
                ..._trafficKey!,
                ..._authentication!.context,
                ...RoomAuthentication.epochBytes(_epoch),
                ...identity!.public.bytes,
              ]);
        final certifiedGrant = identity == null
            ? grant
            : Uint8List.fromList([
                ...grant,
                ...await identity!.sign(
                  _identityProof('host', id, pending.keys, grant),
                ),
              ]);
        final encrypted = await cipher.encrypt(
          certifiedGrant,
          associatedData: id,
        );
        final response = _emit(4, id, [
          ...encrypted.nonce,
          ...encrypted.ciphertext,
        ]);
        if (response != null && grantEpoch == _epoch) {
          while (_completed.length >= max(10, maxPending * 2)) {
            _completed.remove(_completed.keys.first);
          }
          _completed[transcript] = _CompletedAdmission(
            pending.hello,
            response,
            now,
          );
        }
      }
    } else {
      if (frame.senderId != 1 ||
          !Spake2Keys.equal(id, _attemptToken ?? token)) {
        return;
      }
      if (kind == 2 && body.length == 97 && _client != null) {
        final client = _client!;
        _client = null;
        final keys = client.finish(
          Uint8List.sublistView(body, 0, 65),
          a: a,
          b: b,
        );
        if (!Spake2Keys.equal(body.sublist(65), keys.confirmB)) return;
        _clientKeys = keys;
        if (identity == null) {
          _emit(3, id, keys.confirmA);
        } else {
          final cipher = await _wrapCipher(keys);
          final claims = Uint8List.fromList([
            ...token,
            ...identity!.public.bytes,
          ]);
          final credentials = await cipher.encrypt(
            Uint8List.fromList([
              ...claims,
              ...await identity!.sign(
                _identityProof('member', id, keys, claims),
              ),
            ]),
            associatedData: id,
          );
          _emit(3, id, [
            ...keys.confirmA,
            ...credentials.nonce,
            ...credentials.ciphertext,
          ]);
        }
      } else if (kind == 4 &&
          body.length == (identity == null ? 60 : 208) &&
          _clientKeys != null) {
        final cipher = await _wrapCipher(_clientKeys!);
        final grant = await cipher.decrypt(
          EncryptedPacket(
            nonce: Uint8List.sublistView(body, 0, 12),
            ciphertext: Uint8List.sublistView(body, 12),
          ),
          associatedData: id,
        );
        if (_closed || !Spake2Keys.equal(id, _attemptToken ?? token)) return;
        final key = Uint8List.fromList(grant.sublist(0, 32));
        if (identity != null) {
          if (grant.length != 180) return;
          final host = MemberPublicIdentity.decode(grant.sublist(52, 116));
          if (!await host.verify(
            _identityProof(
              'host',
              id,
              _clientKeys!,
              Uint8List.sublistView(grant, 0, 116),
            ),
            grant.sublist(116),
          )) {
            return;
          }
          final context = Uint8List.fromList(grant.sublist(32, 48));
          final epoch = ByteData.sublistView(grant).getUint32(48);
          final old = _authentication;
          if (epoch < _epoch ||
              (old != null &&
                  (!Spake2Keys.equal(old.host.bytes, host.bytes) ||
                      !Spake2Keys.equal(old.context, context)))) {
            throw StateError('Room identity or epoch changed during reconnect');
          }
          _authentication ??= RoomAuthentication(
            self: identity!,
            context: context,
            host: host,
          );
          _epoch = epoch;
        }
        final changedKey =
            _trafficKey == null || !Spake2Keys.equal(_trafficKey!, key);
        final nextCodec = changedKey ? await _codec(key) : _trafficCodec!;
        // Key construction can yield too: a route retry must not let this old
        // response replace the current attempt's codec or finish admission.
        if (_closed || !Spake2Keys.equal(id, _attemptToken ?? token)) return;
        _ready = true;
        _outboundHandshake = null;
        _clientKeys = null;
        // PAKE restores admission, not a new traffic-key epoch. Preserve both
        // replay windows and our nonce counter when the host returns the same
        // key. The session may temporarily clear its codec while reconnecting.
        if (changedKey) {
          _trafficKey?.fillRange(0, _trafficKey!.length, 0);
          _trafficKey = Uint8List.fromList(key);
          _trafficCodec = nextCodec;
        }
        if (!_closed) await onReady(_trafficCodec!);
      }
    }
  }

  Future<SecureFrameCodec> _codec(Uint8List key) async => SecureFrameCodec(
    await SessionCipher.fromKey(key),
    authentication: _authentication,
    epoch: _epoch,
  );

  /// Serialise membership changes, so two leaves cannot publish competing keys.
  Future<void> revoke(Set<int> ids) {
    final next = _rotation.then((_) async {
      if (_closed || !_host || _authentication == null) return;
      for (final id in ids) {
        _authentication!.members.remove(id);
        _keyGrants.remove(id);
      }
      await _rotate();
    });
    _rotation = next.catchError((Object _) {});
    return next;
  }

  Future<void> promote() async {
    if (_authentication == null) return;
    if (_authentication!.host.id != identity!.public.id) {
      throw StateError('Not the certified successor');
    }
    _host = true;
    _ready = true;
    _pending.clear();
    await _rotate();
  }

  Future<void> _rotate() async {
    final auth = _authentication!;
    final key = Uint8List.fromList(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    );
    final epoch = _epoch + 1;
    final grants = <int, (Frame, int)>{};
    for (final entry in auth.members.entries) {
      if (entry.value.identity.id == identity!.public.id) continue;
      final target = entry.value.token;
      final header = Uint8List.fromList([
        ...auth.context,
        ...target,
        ...RoomAuthentication.epochBytes(epoch),
      ]);
      final signed = [...header, ...key];
      final wrapping = await SessionCipher.fromKey(
        await identity!.wrappingKey(entry.value.identity, auth.context),
      );
      final packet = await wrapping.encrypt(
        Uint8List.fromList([...key, ...await identity!.sign(signed)]),
        associatedData: header,
      );
      grants[entry.key] = (
        Frame(
          type: FrameType.handshakeConfirm,
          senderId: 1,
          seq: RelayBudget.maximum << 8,
          payload: Uint8List.fromList([
            3,
            5,
            ...target,
            ...RoomAuthentication.epochBytes(epoch),
            ...packet.nonce,
            ...packet.ciphertext,
          ]),
        ),
        0,
      );
    }
    if (_closed) return;
    _completed.clear();
    _epoch = epoch;
    _trafficKey?.fillRange(0, _trafficKey!.length, 0);
    _trafficKey = key;
    _trafficCodec = await _codec(key);
    _keyGrants
      ..clear()
      ..addAll(grants);
    // Install locally before peers can answer with new-epoch heartbeats.
    await onReady(_trafficCodec!);
    retryKeyGrants();
  }

  Future<void> _acceptKeyGrant(Uint8List target, Uint8List body) async {
    final auth = _authentication;
    if (auth == null ||
        !Spake2Keys.equal(target, token) ||
        body.length != 128) {
      return;
    }
    final epoch = ByteData.sublistView(body).getUint32(0);
    if (epoch <= _epoch) return;
    final header = Uint8List.fromList([
      ...auth.context,
      ...target,
      ...body.take(4),
    ]);
    final cipher = await SessionCipher.fromKey(
      await identity!.wrappingKey(auth.host, auth.context),
    );
    final plaintext = await cipher.decrypt(
      EncryptedPacket(
        nonce: Uint8List.sublistView(body, 4, 16),
        ciphertext: Uint8List.sublistView(body, 16),
      ),
      associatedData: header,
    );
    final key = Uint8List.fromList(plaintext.sublist(0, 32));
    if (!await auth.host.verify([...header, ...key], plaintext.sublist(32))) {
      return;
    }
    if (_closed || epoch <= _epoch) return;
    _epoch = epoch;
    _trafficKey?.fillRange(0, _trafficKey!.length, 0);
    _trafficKey = key;
    _trafficCodec = await _codec(key);
    await onReady(_trafficCodec!);
  }

  /// Bounded retry on the room heartbeat; a valid current-epoch frame ACKs the
  /// grant. A long-offline member can also recover through a fresh PAKE.
  void retryKeyGrants() {
    if (_closed) return;
    for (final entry in _keyGrants.entries.toList()) {
      if (entry.value.$2 >= 30) {
        _keyGrants.remove(entry.key);
      } else {
        final grant = entry.value.$1;
        // Each retry has a fresh wire id, so a gateway which received an
        // earlier copy does not suppress repair of a loss on its next hop.
        send(
          Frame(
            type: grant.type,
            senderId: grant.senderId,
            seq: (RelayBudget.maximum << 8) | entry.value.$2,
            payload: grant.payload,
          ),
        );
        _keyGrants[entry.key] = (entry.value.$1, entry.value.$2 + 1);
      }
    }
  }

  void acknowledgeEpoch(int memberId) => _keyGrants.remove(memberId);

  List<int> _identityProof(
    String role,
    Uint8List attempt,
    Spake2Keys keys,
    Uint8List claims,
  ) => [
    ...utf8.encode('DawnMesh PAKE $role possession v3\u0000'),
    ...attempt,
    ...keys.confirmA,
    ...keys.confirmB,
    ...claims,
  ];

  Future<SessionCipher> _wrapCipher(Spake2Keys keys) => SessionCipher.fromKey(
    Spake2Keys.hkdf(keys.sharedKey, 'DawnMesh traffic key wrapping v$_version'),
  );

  void close() {
    _closed = true;
    _trafficKey?.fillRange(0, _trafficKey!.length, 0);
    _trafficKey = null;
    _trafficCodec = null;
    _pending.clear();
    _completed.clear();
    _outboundHandshake = null;
    _keyGrants.clear();
    _authentication = null;
    _client = null;
    _clientKeys = null;
  }
}

class _Pending {
  final Spake2Keys keys;
  final DateTime created;
  final String hello;
  final Uint8List challenge;
  _Pending(this.keys, this.created, this.hello, this.challenge);
}

class _CompletedAdmission {
  final String hello;
  final Frame response;
  final DateTime created;
  _CompletedAdmission(this.hello, this.response, this.created);
}
