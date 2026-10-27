import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../security/member_identity.dart';
import 'courier_envelope.dart';

class CourierContact {
  const CourierContact(this.name, this.identity);
  final String name;
  final MemberPublicIdentity identity;
}

class CourierItem {
  const CourierItem(this.envelope, this.hops, this.sendsLeft, [this.localText]);
  final String? localText;
  final CourierEnvelope envelope;
  final int hops;
  final int sendsLeft;
}

/// Bounded encrypted native storage; no chat/audio is collected automatically.
/// Sender and recipient keys remain visible to carriers as routing metadata.
class CourierStore extends ChangeNotifier {
  CourierStore({
    required this.identity,
    required this.read,
    required this.write,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final MemberIdentity identity;
  final Future<String?> Function() read;
  final Future<void> Function(String) write;
  final DateTime Function() now;
  static const capacity = 64,
      byteCapacity = 256 * 1024,
      maxHops = 4,
      maxSends = 8;
  static CourierStore? current;
  static Future<CourierStore>? _loading;
  static Future<CourierStore> open({MemberIdentity? identity}) =>
      _loading ??= _open(identity).onError((Object error, StackTrace stack) {
        _loading = null;
        Error.throwWithStackTrace(error, stack);
      });
  static Future<CourierStore> _open(MemberIdentity? identity) async {
    const storage = FlutterSecureStorage();
    final store = CourierStore(
      identity: identity ?? await MemberIdentity.load(),
      read: () => storage.read(key: 'courier_store_v1'),
      write: (data) => storage.write(key: 'courier_store_v1', value: data),
    );
    await store.load();
    current = store;
    return store;
  }

  bool _enabled = false;
  bool get enabled => _enabled;
  final _items = <String, CourierItem>{};
  final _contacts = <String, CourierContact>{};
  List<CourierItem> get items => List.unmodifiable(
    _items.values.where(
      (item) => item.envelope.expiresMs > now().millisecondsSinceEpoch,
    ),
  );
  List<CourierContact> get contacts => List.unmodifiable(_contacts.values);
  String? error;
  Future<void> _queue = Future.value();
  int _queued = 0;

  Future<void> load() async {
    final raw = await read();
    if (raw == null) return;
    if (raw.length > byteCapacity * 2) {
      throw const FormatException('Courier storage size');
    }
    final data = jsonDecode(raw) as Map<String, dynamic>;
    if (data['version'] != 1 ||
        data['identity'] != identity.public.id ||
        data['enabled'] is! bool ||
        data['items'] is! List ||
        data['contacts'] is! List ||
        (data['items'] as List).length > capacity ||
        (data['contacts'] as List).length > capacity) {
      throw const FormatException('Courier storage schema or identity changed');
    }
    _enabled = data['enabled'] as bool;
    for (final entry in data['contacts'] as List) {
      final key = MemberPublicIdentity.decode(
        base64Decode(entry['key'] as String),
      );
      final name = entry['name'] as String;
      if (name.length > 64) throw const FormatException('Contact name');
      _contacts[key.id] = CourierContact(name, key);
    }
    for (final entry in data['items'] as List) {
      final envelope = await CourierEnvelope.verify(
        base64Decode(entry['wire'] as String),
        now(),
      );
      if (envelope == null) {
        continue; // Expired or unauthentic data never re-enters circulation.
      }
      final hops = entry['hops'], sends = entry['sends'];
      if (hops is! int ||
          sends is! int ||
          hops < 0 ||
          hops > maxHops ||
          sends < 0 ||
          sends > maxSends) {
        throw const FormatException('Courier budget');
      }
      final previous = _items[envelope.key];
      if (previous?.envelope.revoked == true && !envelope.revoked) continue;
      final localText = entry['localText'];
      if (localText != null &&
          (localText is! String ||
              utf8.encode(localText).length > CourierEnvelope.maxTextBytes ||
              envelope.author.id != identity.public.id)) {
        throw const FormatException('Local message');
      }
      _items[envelope.key] = CourierItem(
        envelope,
        hops,
        sends,
        localText as String?,
      );
    }
    if (_items.length != (data['items'] as List).length) await write(_encode());
  }

  Future<void> purgeExpired() async {
    if (_items.values.any(
      (item) => item.envelope.expiresMs <= now().millisecondsSinceEpoch,
    )) {
      await _change<void>(() {});
    }
  }

  String _encode() => jsonEncode({
    'version': 1,
    'identity': identity.public.id,
    'enabled': _enabled,
    'contacts': [
      for (final contact in _contacts.values)
        {'name': contact.name, 'key': base64Encode(contact.identity.bytes)},
    ],
    'items': [
      for (final item in _items.values)
        {
          'wire': base64Encode(item.envelope.wire),
          'hops': item.hops,
          'sends': item.sendsLeft,
          'localText': item.localText,
        },
    ],
  });

  Future<T> _change<T>(FutureOr<T> Function() action) {
    if (_queued >= 16) return Future.error(StateError('Courier is busy'));
    _queued++;
    final next = _queue.then((_) async {
      final oldItems = Map.of(_items), oldContacts = Map.of(_contacts);
      final wasEnabled = _enabled;
      try {
        _items.removeWhere(
          (_, item) => item.envelope.expiresMs <= now().millisecondsSinceEpoch,
        );
        final value = await action();
        final encoded = _encode();
        if (utf8.encode(encoded).length > byteCapacity) {
          throw StateError('Courier storage quota reached');
        }
        await write(encoded);
        error = null;
        notifyListeners();
        return value;
      } catch (e) {
        _items
          ..clear()
          ..addAll(oldItems);
        _contacts
          ..clear()
          ..addAll(oldContacts);
        _enabled = wasEnabled;
        error = '离线转交暂时不可用，请重试。';
        notifyListeners();
        rethrow;
      } finally {
        _queued--;
      }
    });
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> setEnabled(bool value) => _change(() {
    _enabled = value;
  });
  Future<void> rememberContact(String name, MemberPublicIdentity key) =>
      _change(() {
        if (name.length > 64 ||
            (!_contacts.containsKey(key.id) && _contacts.length >= capacity)) {
          throw StateError('Contact quota reached');
        }
        final old = _contacts[key.id];
        if (old != null && old.identity.fingerprint != key.fingerprint) {
          throw StateError('Contact keys changed');
        }
        _contacts[key.id] = CourierContact(name, key);
      });
  Future<void> forgetContact(String id) => _change(() {
    _contacts.remove(id);
  });

  Future<void> compose(String recipientId, String text) => _change(() async {
    if (!_enabled) throw StateError('Courier is disabled');
    final recipient = _contacts[recipientId];
    if (recipient == null) throw StateError('Remember this contact first');
    if (_items.length >= capacity) throw StateError('Courier quota reached');
    final envelope = await CourierEnvelope.create(
      author: identity,
      recipient: recipient.identity,
      text: text,
      now: now(),
    );
    _items[envelope.key] = CourierItem(
      envelope,
      maxHops,
      maxSends,
      text.trim(),
    );
  });

  Future<bool> accept(Uint8List wire, int hops) => _change(() async {
    if (!_enabled || hops < 1 || hops > maxHops) return false;
    final envelope = await CourierEnvelope.verify(wire, now());
    if (envelope == null) return false;
    final previous = _items[envelope.key];
    if (previous != null && (previous.envelope.revoked || !envelope.revoked)) {
      return false;
    }
    if (previous == null && _items.length >= capacity) return false;
    // A signature for another random ID cannot erase an existing message.
    if (previous != null &&
        (previous.envelope.recipient.fingerprint !=
                envelope.recipient.fingerprint ||
            previous.envelope.createdMs != envelope.createdMs ||
            previous.envelope.expiresMs != envelope.expiresMs)) {
      return false;
    }
    _items[envelope.key] = CourierItem(
      envelope,
      envelope.recipient.id == identity.public.id && !envelope.revoked
          ? 0
          : hops - 1,
      maxSends,
    );
    return true;
  });

  Future<void> revoke(String key) => _change(() async {
    final old = _items[key];
    if (old == null) return;
    final envelope = await old.envelope.revoke(identity);
    _items[key] = CourierItem(envelope, maxHops, maxSends);
  });

  List<String> get inventory =>
      !_enabled
            ? []
            : items
                  .where((item) => item.hops > 0 && item.sendsLeft > 0)
                  .map((item) => item.envelope.digest)
                  .toList()
        ..sort();
  bool containsDigest(String digest) =>
      items.any((item) => item.envelope.digest == digest);

  /// Persist the local copy budget before sending, so restarts cannot refill it.
  Future<Uint8List?> takeForSend(String digest) => _change(() {
    if (!_enabled) return null;
    final item = items
        .where(
          (i) => i.envelope.digest == digest && i.hops > 0 && i.sendsLeft > 0,
        )
        .firstOrNull;
    if (item == null) return null;
    _items[item.envelope.key] = CourierItem(
      item.envelope,
      item.hops,
      item.sendsLeft - 1,
      item.localText,
    );
    return Uint8List.fromList([item.hops, ...item.envelope.wire]);
  });

  /// Explicit local deletion also disables carrying; remote copies expire or
  /// obey an author revocation, but cannot be remotely erased by this action.
  Future<void> clear() => _change(() {
    _enabled = false;
    _items.clear();
    _contacts.clear();
  });
}
