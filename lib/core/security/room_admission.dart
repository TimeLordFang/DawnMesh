import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import '../protocol/frame.dart';
import '../protocol/frame_type.dart';
import 'session_crypto.dart';
import 'session_handshake.dart';
import 'spake2.dart';

/// Broadcast-safe PAKE admission. Only an authenticated PAKE peer receives the
/// room's independent random traffic key. No PIN verifier is put on the wire.
class RoomAdmission {
  final BigInt passwordScalar;
  final Uint8List token;
  final void Function(Frame) send;
  final Future<void> Function(SecureFrameCodec) onReady;
  bool _host = false;
  bool _closed = false;
  bool _ready = false;
  Uint8List? _trafficKey;
  Spake2? _client;
  Spake2Keys? _clientKeys;
  final Map<String, _Pending> _pending = {};
  final List<DateTime> _attempts = [];
  int _totalAttempts = 0;

  RoomAdmission({
    required this.passwordScalar,
    required this.token,
    required this.send,
    required this.onReady,
  });

  Future<void> startHost() async {
    _host = true;
    final random = Random.secure();
    _trafficKey = Uint8List.fromList(
      List.generate(32, (_) => random.nextInt(256)),
    );
    await onReady(SecureFrameCodec(await SessionCipher.fromKey(_trafficKey!)));
  }

  void startClient() {
    _client = Spake2(isA: true, passwordScalar: passwordScalar);
    _emit(1, token, _client!.message);
  }

  void _emit(int kind, Uint8List id, List<int> body) {
    if (_closed) return;
    send(
      Frame(
        type: kind <= 2 ? FrameType.handshakeHello : FrameType.handshakeConfirm,
        senderId: _host ? 1 : 0,
        seq: 0,
        payload: Uint8List.fromList([2, kind, ...id, ...body]),
      ),
    );
  }

  (Uint8List, Uint8List) _identities(Uint8List id) => (
    Uint8List.fromList([...utf8.encode('DawnMesh PIN v2 client\u0000'), ...id]),
    Uint8List.fromList(utf8.encode('DawnMesh PIN v2 host')),
  );

  Future<void> handle(Frame frame) async {
    if (_closed || (!_host && _ready)) return;
    final p = frame.payload;
    if (p.length < 18 || p[0] != 2) return;
    final kind = p[1];
    if (frame.type !=
        (kind <= 2 ? FrameType.handshakeHello : FrameType.handshakeConfirm)) {
      return;
    }
    final id = Uint8List.fromList(p.sublist(2, 18));
    final body = Uint8List.fromList(p.sublist(18));
    final index = base64.encode(id);
    final (a, b) = _identities(id);
    if (_host) {
      if (frame.senderId != 0) return;
      final now = DateTime.now();
      _pending.removeWhere(
        (_, pending) => now.difference(pending.created).inSeconds >= 12,
      );
      if (kind == 1 && body.length == 65) {
        _attempts.removeWhere((time) => now.difference(time).inSeconds >= 60);
        if (_pending.containsKey(index) ||
            _pending.length >= 5 ||
            _attempts.length >= 10 ||
            _totalAttempts >= 120) {
          return;
        }
        _attempts.add(now);
        _totalAttempts++;
        final server = Spake2(isA: false, passwordScalar: passwordScalar);
        final keys = server.finish(body, a: a, b: b);
        _pending[index] = _Pending(keys, now);
        _emit(2, id, [...server.message, ...keys.confirmB]);
      } else if (kind == 3 && body.length == 32) {
        final pending = _pending.remove(
          index,
        ); // A confirmation gets one attempt.
        if (pending == null || !Spake2Keys.equal(body, pending.keys.confirmA)) {
          return;
        }
        final cipher = await _wrapCipher(pending.keys);
        final encrypted = await cipher.encrypt(
          _trafficKey!,
          associatedData: id,
        );
        _emit(4, id, [...encrypted.nonce, ...encrypted.ciphertext]);
      }
    } else {
      if (frame.senderId != 1 || !Spake2Keys.equal(id, token)) return;
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
        _emit(3, id, keys.confirmA);
      } else if (kind == 4 && body.length == 60 && _clientKeys != null) {
        final cipher = await _wrapCipher(_clientKeys!);
        final key = await cipher.decrypt(
          EncryptedPacket(
            nonce: Uint8List.sublistView(body, 0, 12),
            ciphertext: Uint8List.sublistView(body, 12),
          ),
          associatedData: id,
        );
        if (_closed) return;
        _ready = true;
        _clientKeys = null;
        await onReady(SecureFrameCodec(await SessionCipher.fromKey(key)));
      }
    }
  }

  Future<SessionCipher> _wrapCipher(Spake2Keys keys) => SessionCipher.fromKey(
    Spake2Keys.hkdf(keys.sharedKey, 'DawnMesh traffic key wrapping v2'),
  );

  void close() {
    _closed = true;
    _trafficKey?.fillRange(0, _trafficKey!.length, 0);
    _trafficKey = null;
    _pending.clear();
    _client = null;
    _clientKeys = null;
  }
}

class _Pending {
  final Spake2Keys keys;
  final DateTime created;
  _Pending(this.keys, this.created);
}
