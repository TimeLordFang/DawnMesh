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
    this.availability,
    this.changed,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final Future<String> Function()? availability;
  final void Function()? changed;
  String status = '正在准备直连';
  void _status(String value) {
    if (status == value || _closed) return;
    status = value;
    changed?.call();
  }

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
      _status('直连暂不可用，自动重试中');
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
    final ready = await availability?.call() ?? 'ready';
    if (_closed) return;
    if (ready != 'ready') {
      _status(switch (ready) {
        'permission' => '直连需要附近设备权限，请在系统设置中允许',
        'wifi_off' => '请打开 Wi-Fi 后自动重试直连',
        'location_off' => '请打开系统定位后自动重试直连',
        _ => '当前设备不支持自动 Wi-Fi 直连',
      });
      return;
    }
    final current = await info();
    if (_closed) return;
    if (current.groupFormed) {
      // A process restart or an older native retry may leave this same room's
      // group alive. Adopt only the exact room-derived SSID, never another one.
      if (current.networkName.isNotEmpty) {
        _ownsGroup = current.networkName == credentials.networkName;
      }
      _status(
        _ownsGroup
            ? (current.isGroupOwner ? 'Wi-Fi 直连入口已就绪，等待队友连接' : '已加入直连群组，正在连接房间')
            : '正在尝试现有局域网直连',
      );
      if (selfId == hostId && _ownsGroup && current.isGroupOwner) {
        await signal({'kind': 'wifi_ready', ...credentials.toMap()});
      }
      return;
    }
    if (_retryAfter != null && now().isBefore(_retryAfter!)) return;
    if (selfId != hostId &&
        (_readyUntil == null || now().isAfter(_readyUntil!))) {
      _status('等待房主建立 Wi-Fi 直连');
      return;
    }
    _status(selfId == hostId ? '正在建立 Wi-Fi 直连' : '正在连接房主 Wi-Fi');
    _retryAfter = now().add(const Duration(seconds: 15));
    final accepted = selfId == hostId
        ? await create(credentials)
        : await join(credentials);
    _ownsGroup = _ownsGroup || accepted;
    if (!accepted) _status('直连建链未完成，自动重试中');
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
