import 'dart:async';

import '../transport/wifi_direct_credentials.dart';
import '../transport/wifi_direct_manager.dart';
import '../diagnostics/app_log.dart';

/// Host readiness is delivered over the encrypted Internet signaling channel.
/// Guests never create a group and only attempt a join after its owner is ready.
class HybridWifiLink {
  HybridWifiLink({
    required this.selfId,
    required this.hostId,
    required this.credentials,
    required this.signal,
    required this.info,
    required this.create,
    required this.join,
    required this.disconnect,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final String selfId, hostId;
  final WifiDirectCredentials credentials;
  final Future<void> Function(Map<String, dynamic>) signal;
  final Future<WifiP2pConnectionInfo> Function() info;
  final Future<bool> Function(WifiDirectCredentials) create, join;
  final Future<bool> Function() disconnect;
  final DateTime Function() now;
  Timer? _timer;
  Future<void>? _busy;
  bool _closed = false, _ownsGroup = false;
  DateTime? _readyUntil, _retryAfter;
  void start() {
    _timer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(tick()),
    );
    unawaited(tick());
  }

  void receive(String from, Map<String, dynamic> data) {
    if (_closed ||
        from != hostId ||
        selfId == hostId ||
        data['kind'] != 'wifi_ready' ||
        data['networkName'] != credentials.networkName ||
        data['passphrase'] != credentials.passphrase) {
      return;
    }
    _readyUntil = now().add(const Duration(seconds: 15));
    unawaited(tick());
  }

  Future<void> tick() {
    if (_closed) return Future.value();
    if (_busy != null) return _busy!;
    final task = _tick().catchError((Object error) {
      AppLog.warn('Hybrid', '自动直连暂未就绪，继续使用公网：$error');
    });
    late final Future<void> settled;
    settled = task.whenComplete(() {
      if (identical(_busy, settled)) _busy = null;
    });
    _busy = settled;
    return settled;
  }

  Future<void> _tick() async {
    final current = await info();
    if (_closed) return;
    if (current.groupFormed) {
      if (selfId == hostId && _ownsGroup && current.isGroupOwner) {
        await signal({'kind': 'wifi_ready', ...credentials.toMap()});
      }
      return;
    }
    if (_retryAfter != null && now().isBefore(_retryAfter!)) return;
    if (selfId != hostId &&
        (_readyUntil == null || now().isAfter(_readyUntil!))) {
      return;
    }
    _retryAfter = now().add(const Duration(seconds: 15));
    final accepted = selfId == hostId
        ? await create(credentials)
        : await join(credentials);
    _ownsGroup = _ownsGroup || accepted;
  }

  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    await _busy;
    if (_ownsGroup) {
      await disconnect();
      _ownsGroup = false;
    }
  }
}
