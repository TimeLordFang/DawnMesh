import 'dart:typed_data';

import '../diagnostics/app_log.dart';
import '../protocol/frame.dart';
import '../protocol/frame_type.dart';
import 'courier_envelope.dart';
import 'courier_store.dart';

/// Exact, paged digest reconciliation. Never use probabilistic membership to
/// suppress an undelivered message. Two envelopes per six-second interval bound
/// background work so voice and room controls retain their normal budget.
class CourierLink {
  CourierLink({
    required this.store,
    required this.selfId,
    required this.members,
    required this.send,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final CourierStore store;
  final int Function() selfId;
  final Set<int> Function() members;
  final Future<void> Function(FrameType, Uint8List) send;
  final DateTime Function() now;
  int _tick = 0, _page = 0, _sendBudget = 2;
  bool _busy = false;
  final _received = <int, (DateTime, int)>{};
  final _lastControl = <(int, int), DateTime>{};

  Future<void> tick() async {
    if (!store.enabled || ++_tick % 3 != 0) return;
    _sendBudget = 2;
    _received.removeWhere((peer, _) => !members().contains(peer));
    _lastControl.removeWhere((key, _) => !members().contains(key.$1));
    final all = store.inventory;
    final pages = (all.length + 7) ~/ 8;
    final start = pages == 0 ? 0 : (_page++ % pages) * 8;
    try {
      await store.purgeExpired();
      await _control(1, 0, all.skip(start).take(8).toList());
    } catch (error) {
      AppLog.warn('离线转交', '清单暂未发出：$error');
    }
  }

  Future<void> handle(Frame frame) async {
    if (_busy ||
        !store.enabled ||
        frame.senderId == selfId() ||
        !members().contains(frame.senderId)) {
      return;
    }
    final bytes = frame.payload;
    if (frame.type == FrameType.courierBundle) {
      if (bytes.length < 2 ||
          bytes.length > CourierEnvelope.maxWireBytes + 2 ||
          bytes[0] != selfId()) {
        return;
      }
      // Per-member rate limit before signature or storage work.
      final window = _received[frame.senderId];
      final count =
          window == null ||
              now().difference(window.$1) >= const Duration(seconds: 5)
          ? 0
          : window.$2;
      if (count >= 2) return;
      _received[frame.senderId] = (count == 0 ? now() : window!.$1, count + 1);
      _busy = true;
      try {
        await store.accept(Uint8List.sublistView(bytes, 2), bytes[1]);
      } catch (error) {
        AppLog.warn('离线转交', '密文未保存：$error');
      } finally {
        _busy = false;
      }
      return;
    }
    if (bytes.length < 4 ||
        bytes[0] != 1 ||
        bytes[1] < 1 ||
        bytes[1] > 2 ||
        (bytes[2] != 0 && bytes[2] != selfId()) ||
        bytes[3] > 8 ||
        bytes.length != 4 + bytes[3] * 16) {
      return;
    }
    if (!_allow(frame.senderId, bytes[1], const Duration(seconds: 5))) return;
    final ids = [
      for (var offset = 4; offset < bytes.length; offset += 16)
        bytes
            .sublist(offset, offset + 16)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(),
    ];
    _busy = true;
    try {
      if (bytes[1] == 1) {
        final missing = ids
            .where((id) => !store.containsDigest(id))
            .take(2)
            .toList();
        if (missing.isNotEmpty) await _control(2, frame.senderId, missing);
      } else {
        for (final id in ids.take(2)) {
          if (_sendBudget <= 0) break;
          _sendBudget--;
          final bundle = await store.takeForSend(id);
          if (bundle != null) {
            await send(
              FrameType.courierBundle,
              Uint8List.fromList([frame.senderId, ...bundle]),
            );
          }
        }
      }
    } catch (error) {
      AppLog.warn('离线转交', '本轮转交暂停：$error');
    } finally {
      _busy = false;
    }
  }

  bool _allow(int peer, int kind, Duration interval) {
    final previous = _lastControl[(peer, kind)];
    if (previous != null && now().difference(previous) < interval) return false;
    _lastControl[(peer, kind)] = now();
    return true;
  }

  Future<void> _control(int kind, int target, List<String> ids) => send(
    FrameType.courierControl,
    Uint8List.fromList([
      1,
      kind,
      target,
      ids.length,
      for (final id in ids)
        for (var i = 0; i < id.length; i += 2)
          int.parse(id.substring(i, i + 2), radix: 16),
    ]),
  );
}
