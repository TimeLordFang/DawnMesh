import 'dart:async';

import 'package:flutter/services.dart';

import '../diagnostics/app_log.dart';

/// 把 Android 原生音频、BLE 与 Wi-Fi Direct 诊断送进应用内日志总线。
class NativeDebugLogChannel {
  NativeDebugLogChannel._();

  static const _events = EventChannel('dev.dawnmesh.intercom/debug_logs');
  static StreamSubscription<dynamic>? _subscription;

  static void start() {
    _subscription ??= _events.receiveBroadcastStream().listen(
      _handleEvent,
      // 非 Android 平台或 widget tests 没有原生实现，静默忽略即可。
      onError: (_) {},
    );
  }

  static void _handleEvent(dynamic event) {
    if (event is! Map) return;
    final level = switch (event['level']) {
      'debug' => LogLevel.debug,
      'warn' => LogLevel.warn,
      'error' => LogLevel.error,
      _ => LogLevel.info,
    };
    final tag = event['tag'];
    final message = event['message'];
    if (tag is! String || message is! String) return;
    AppLog.native(level, tag, message, event['error']);
  }
}
