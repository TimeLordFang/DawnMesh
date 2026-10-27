import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../protocol/frame.dart';
import '../protocol/frame_type.dart';

enum ChatDelivery { sent, pending, delivered, failed }

/// Session-only, author-owned repair. Inventories contain exact 128-bit packet
/// digests packed as bytes, not probabilistic filters: no false-positive loss.
/// Older clients still read the unchanged chat payload; they never count as ACKed.
class ReliableChat {
  ReliableChat({
    required this.selfId,
    required this.members,
    required this.emit,
    required this.changed,
    required this.nextSeq,
    this.acceptsMedia,
    this.memberAcceptsMedia,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final int Function() selfId;
  final Set<int> Function() members;
  final void Function(Frame) emit;
  final void Function() changed;
  final int Function() nextSeq;
  final bool Function()? acceptsMedia;
  final bool Function(int)? memberAcceptsMedia;
  final DateTime Function() now;
  static const capacity = 200;
  static const mediaCapacity = 512;
  static const lifetime = Duration(minutes: 30);
  static const _pageSize = 12;
  static const _inventory = 1, _want = 2, _ack = 3;
  final _own = <String, _Delivery>{};
  final _seen = <String, DateTime>{};
  final _retiredStatus = <String, ChatDelivery>{};
  final _pendingAcks = <int, Set<String>>{};
  final _capable = <int, DateTime>{};
  final _lastControl = <(int, int), DateTime>{};
  int _page = 0;
  int _mediaPage = 0;
  int _ticks = 0;
  int _retryCursor = 0;

  static String packetId(Frame frame) =>
      _hex(sha256.convert(frame.encode()).bytes.take(16));

  static String _hex(Iterable<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  void remember(Frame frame, {String? messageId}) {
    if (frame.type != FrameType.chat &&
        frame.type != FrameType.chatDelete &&
        frame.type != FrameType.voiceNote) {
      return;
    }
    _own[packetId(frame)] = _Delivery(
      frame,
      messageId,
      now(),
      members()
          .where(
            (id) =>
                id != selfId() &&
                _capable.containsKey(id) &&
                (!frame.type.isBulk || memberAcceptsMedia?.call(id) != false),
          )
          .toSet(),
    );
    final media = frame.type.isBulk;
    final sameKind = _own.entries
        .where((e) => e.value.frame.type.isBulk == media)
        .map((e) => e.key)
        .toList();
    final limit = media ? mediaCapacity : capacity;
    var count = sameKind.length;
    for (final key in sameKind) {
      if (count <= limit) break;
      final old = _own[key];
      if (old == null) continue;
      final id = old.messageId;
      if (id == null) {
        _own.remove(key);
        count--;
        continue;
      }
      // Evict a complete logical note, never a subset whose remaining ACKs
      // could otherwise falsely report that the whole note was delivered.
      final state = status(id);
      _retiredStatus[id] = state == ChatDelivery.delivered
          ? ChatDelivery.delivered
          : ChatDelivery.failed;
      final before = _own.length;
      _own.removeWhere((_, item) => item.messageId == id);
      count -= before - _own.length;
      while (_retiredStatus.length > capacity) {
        _retiredStatus.remove(_retiredStatus.keys.first);
      }
    }
  }

  /// Retain the recall packet instead of continuing to repair recalled text.
  void forgetMessage(String messageId) {
    _own.removeWhere((_, item) => item.messageId == messageId);
    _retiredStatus.remove(messageId);
  }

  /// Called only after message validation. ACK duplicates again, since an ACK
  /// may have been lost. ACKs never themselves trigger another ACK.
  void received(Frame frame) {
    final id = packetId(frame);
    _seen[id] = now();
    while (_seen.length > (capacity + mediaCapacity) * 2) {
      _seen.remove(_seen.keys.first);
    }
    if (frame.type.isBulk) {
      final pending = _pendingAcks.putIfAbsent(
        frame.senderId,
        () => <String>{},
      );
      pending.add(id);
      if (pending.length >= _pageSize) _flushAcks(frame.senderId);
    } else {
      _control(_ack, frame.senderId, [id]);
    }
  }

  ChatDelivery? status(String messageId) {
    final states = _own.values
        .where((v) => v.messageId == messageId)
        .map(_status)
        .toList();
    if (states.isEmpty) return _retiredStatus[messageId];
    if (states.every((s) => s == ChatDelivery.delivered)) {
      return ChatDelivery.delivered;
    }
    if (states.contains(ChatDelivery.failed)) return ChatDelivery.failed;
    if (states.contains(ChatDelivery.pending)) return ChatDelivery.pending;
    return ChatDelivery.sent;
  }

  void _flushAcks(int peer) {
    final ids = _pendingAcks.remove(peer);
    if (ids != null && ids.isNotEmpty) _control(_ack, peer, ids.toList());
  }

  ChatDelivery _status(_Delivery item) {
    if (item.expected.isEmpty) return ChatDelivery.sent;
    if (item.expected.every(item.acked.contains)) return ChatDelivery.delivered;
    if (item.attempts >= 8 || now().difference(item.created) > lifetime) {
      return ChatDelivery.failed;
    }
    return ChatDelivery.pending;
  }

  void handle(Frame frame) {
    if (!members().contains(frame.senderId) || frame.senderId == selfId()) {
      return;
    }
    final p = frame.payload;
    // [version, kind, target, count, 16-byte digest ...]
    if (p.length < 4 ||
        p[0] != 1 ||
        (p[1] & 127) < 1 ||
        (p[1] & 127) > 3 ||
        (p[2] != 0 && p[2] != selfId()) ||
        p[3] > _pageSize ||
        p.length != 4 + 16 * p[3]) {
      return;
    }
    final kind = p[1] & 127;
    final mediaFlag = p[1] & 128;
    if (mediaFlag != 0 && acceptsMedia?.call() == false) return;
    final ids = [
      for (var i = 4; i < p.length; i += 16) _hex(p.sublist(i, i + 16)),
    ];
    _capable[frame.senderId] = now();
    if (kind == _ack) {
      var updated = false;
      for (final id in ids) {
        final item = _own[id];
        if (item != null && item.expected.contains(frame.senderId)) {
          updated = item.acked.add(frame.senderId) || updated;
        }
      }
      if (updated) changed();
      return;
    }
    // Inventory and requests have independent limits; a simultaneous inventory
    // must not suppress the request it elicits in the opposite direction.
    final key = (frame.senderId, p[1]);
    final last = _lastControl[key];
    if (last != null &&
        now().difference(last) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastControl[key] = now();
    if (kind == _inventory) {
      final missing = ids.where((id) => !_seen.containsKey(id)).toList();
      if (missing.isNotEmpty) {
        _control(_want | mediaFlag, frame.senderId, missing);
      }
    } else {
      for (final id in ids) {
        final item = _own[id];
        if (item != null &&
            (!item.frame.type.isBulk ||
                memberAcceptsMedia?.call(frame.senderId) != false) &&
            item.repairs < 64 &&
            now().difference(item.created) <= lifetime) {
          item.repairs++;
          emit(item.frame);
        }
      }
    }
  }

  /// Uses the existing heartbeat. No additional timer survives room disposal.
  void tick() {
    _capable.removeWhere(
      (id, time) =>
          !members().contains(id) ||
          now().difference(time) > const Duration(minutes: 1),
    );
    _lastControl.removeWhere((key, _) => !members().contains(key.$1));
    _seen.removeWhere((_, time) => now().difference(time) > lifetime);
    for (final peer in _pendingAcks.keys.toList()) {
      _flushAcks(peer);
    }
    var updated = false;
    var mediaBudget = 8;
    var controlBudget = 16;
    final entries = _own.values.toList();
    final start = entries.isEmpty ? 0 : _retryCursor % entries.length;
    for (var offset = 0; offset < entries.length; offset++) {
      final index = (start + offset) % entries.length;
      final item = entries[index];
      final before = _status(item);
      if (before != ChatDelivery.pending) continue;
      if (now().difference(item.lastSent) >= const Duration(seconds: 6)) {
        if (item.frame.type.isBulk
            ? mediaBudget-- <= 0
            : controlBudget-- <= 0) {
          continue;
        }
        _retryCursor = index + 1;
        item.attempts++;
        item.lastSent = now();
        emit(item.frame);
      }
      updated = before != _status(item) || updated;
    }
    if (++_ticks % 3 == 0) {
      _inventoryPage(media: false, page: _page++);
      if (_own.values.any((item) => item.frame.type.isBulk)) {
        _inventoryPage(media: true, page: _mediaPage++);
      }
    }
    if (updated) changed();
  }

  void _inventoryPage({required bool media, required int page}) {
    final ids = _own.entries
        .where(
          (e) =>
              e.value.frame.type.isBulk == media &&
              now().difference(e.value.created) <= lifetime,
        )
        .map((e) => e.key)
        .toList();
    final pages = (ids.length + _pageSize - 1) ~/ _pageSize;
    final start = pages == 0 ? 0 : (page % pages) * _pageSize;
    _control(
      _inventory | (media ? 128 : 0),
      0,
      ids.skip(start).take(_pageSize).toList(),
    );
  }

  void _control(int kind, int target, List<String> ids) {
    emit(
      Frame(
        type: FrameType.chatControl,
        senderId: selfId(),
        seq: nextSeq(),
        payload: Uint8List.fromList([
          1,
          kind,
          target,
          ids.length,
          for (final id in ids)
            for (var i = 0; i < id.length; i += 2)
              int.parse(id.substring(i, i + 2), radix: 16),
        ]),
      ),
    );
  }

  void clear() {
    _own.clear();
    _retiredStatus.clear();
    _seen.clear();
    _capable.clear();
    _lastControl.clear();
    _pendingAcks.clear();
    _retryCursor = 0;
  }
}

class _Delivery {
  _Delivery(this.frame, this.messageId, this.created, this.expected)
    : lastSent = created;
  final Frame frame;
  final String? messageId;
  final DateTime created;
  DateTime lastSent;
  final Set<int> expected;
  final acked = <int>{};
  int attempts = 1;
  int repairs = 0;
}
