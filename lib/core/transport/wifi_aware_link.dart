import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Optional accelerator. It adds an authenticated fusion socket without changing
/// the existing LAN, cloud or peer Wi-Fi path when setup is unavailable.
class WifiAwareLink extends ChangeNotifier {
  WifiAwareLink({
    required this.localPort,
    required this.roomId,
    required this.isHost,
    required this.connect,
  });
  final int localPort;
  final String roomId;
  final bool Function() isHost;
  final Future<bool> Function(int port) connect;
  static const channel = MethodChannel('dev.dawnmesh.intercom/wifi_aware');
  static const events = EventChannel('dev.dawnmesh.intercom/wifi_aware_events');
  final owner = base64UrlEncode(
    List.generate(12, (_) => Random.secure().nextInt(256)),
  );
  StreamSubscription<dynamic>? _subscription;
  Map<String, dynamic>? capability;
  String status = '未启用';
  String? pairingPeer, displayedPin;
  bool active = false, busy = false, _closed = false;
  int _pendingConnections = 0;
  bool _acceptEvents = false;
  bool? _startedHost;

  Future<void> inspect() async {
    try {
      capability = await channel.invokeMapMethod<String, dynamic>(
        'capabilities',
      );
    } on MissingPluginException {
      capability = {'supported': false, 'reason': '当前安装包未提供 Wi-Fi Aware'};
    } catch (_) {
      capability = {'supported': false, 'reason': '系统暂时无法检查 Wi-Fi Aware'};
    }
    if (!_closed) notifyListeners();
  }

  Future<void> start() async {
    if (_closed || busy || active) return;
    busy = true;
    notifyListeners();
    try {
      await inspect();
      if (capability?['supported'] != true) {
        status = capability?['reason'] as String? ?? '设备不支持';
        return;
      }
      if (Platform.isAndroid) {
        final allowed = await const MethodChannel(
          'dev.dawnmesh.intercom/permissions',
        ).invokeMethod<bool>('ensureWifiAware');
        if (allowed != true) {
          status = '附近 Wi-Fi 权限未允许，原连接继续';
          return;
        }
      }
      _subscription ??= events.receiveBroadcastStream().listen(
        _event,
        onError: (Object _) {
          if (!_closed) {
            status = '加速链路暂不可用，原连接继续';
            active = false;
            _acceptEvents = false;
            notifyListeners();
          }
        },
      );
      _acceptEvents = true;
      _startedHost = isHost();
      final result = await channel.invokeMapMethod<String, dynamic>('start', {
        'owner': owner,
        'roomId': roomId,
        'port': localPort,
        'host': _startedHost,
      });
      if (_closed) {
        await channel.invokeMethod<void>('stop', {'owner': owner});
        return;
      }
      active = result?['started'] == true;
      _acceptEvents = active;
      status =
          result?['status'] as String? ??
          (active ? '等待附近设备与系统配对' : '未能启用，原连接继续');
    } catch (_) {
      _acceptEvents = false;
      active = false;
      try {
        await channel.invokeMethod<void>('stop', {'owner': owner});
      } catch (_) {}
      status = '加速链路暂不可用，原连接继续';
    } finally {
      busy = false;
      if (!_closed) notifyListeners();
    }
  }

  void _event(dynamic event) {
    if (_closed || !_acceptEvents || event is! Map || event['owner'] != owner) {
      return;
    }
    switch (event['type']) {
      case 'endpoint':
        final port = event['port'];
        if (port is int &&
            port > 0 &&
            port <= 65535 &&
            _pendingConnections < 4) {
          _pendingConnections++;
          unawaited(
            connect(port)
                .then((connected) {
                  if (!_closed && _acceptEvents) {
                    status = connected ? 'Wi-Fi Aware 加速已连接' : '加速连接未完成，原连接继续';
                    notifyListeners();
                  }
                })
                .catchError((Object _) {})
                .whenComplete(() => _pendingConnections--),
          );
        }
        break;
      case 'pair':
        pairingPeer = event['peer'] as String?;
        displayedPin = event['pin'] as String?;
        status = event['status'] as String? ?? '请完成系统配对';
        notifyListeners();
        break;
      case 'status':
        status = event['status'] as String? ?? status;
        if (event['active'] is bool) {
          active = event['active'] as bool;
          _acceptEvents = active;
        }
        notifyListeners();
        break;
    }
  }

  Future<void> pair({String? pin}) async {
    if (_closed || !active || busy) return;
    busy = true;
    notifyListeners();
    try {
      await channel.invokeMethod<void>('pair', {
        'owner': owner,
        'peer': pairingPeer,
        'pin': pin,
      });
    } catch (_) {
      status = '配对未完成，原连接继续';
    } finally {
      busy = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<void> checkRole() async {
    if (active && _startedHost != isHost()) {
      await stop();
      status = '房主已变化，可重新启用加速';
      if (!_closed) notifyListeners();
    }
  }

  Future<void> stop() async {
    _acceptEvents = false;
    busy = true;
    active = false;
    try {
      await channel.invokeMethod<void>('stop', {'owner': owner});
    } catch (_) {}
    await _subscription?.cancel();
    _subscription = null;
    active = false;
    pairingPeer = null;
    displayedPin = null;
    status = '未启用';
    busy = false;
    if (!_closed) notifyListeners();
  }

  Future<void> close() async {
    _closed = true;
    await stop();
    super.dispose();
  }
}
