import 'package:flutter/services.dart';

import '../diagnostics/app_log.dart';

/// One foreground microphone session owns the Android lock-screen controls.
class BackgroundCallControls {
  static const channel = MethodChannel('dev.dawnmesh.intercom/call_controls');
  static Object? _owner;
  final Object owner;
  Future<void> Function(String, dynamic)? _command;
  bool _failed = false;
  BackgroundCallControls(this.owner);

  Future<void> bind(Future<void> Function(String, dynamic) command) async {
    _owner = owner;
    _command = command;
    _failed = false;
    channel.setMethodCallHandler((call) async {
      if (identical(_owner, owner)) await command(call.method, call.arguments);
    });
  }

  Future<void> update({
    required bool bluetooth,
    bool internet = false,
    required bool automatic,
    required bool pressed,
    required bool muted,
  }) async {
    if (!identical(_owner, owner) || _failed) return;
    try {
      await channel.invokeMethod('update', {
        'active': true,
        'bluetooth': bluetooth,
        'internet': internet,
        'automatic': automatic,
        'pressed': pressed,
        'muted': muted,
      });
    } on MissingPluginException {
      /* Widget tests / non-Android. */
    } on PlatformException catch (error) {
      if (!identical(_owner, owner) || _failed) return;
      _failed = true;
      AppLog.error(
        'CallControls',
        error.message ?? 'Background calling failed',
      );
      await _command?.call('serviceFailed', error.message);
    }
  }

  Future<void> close() async {
    if (!identical(_owner, owner)) return;
    _owner = null;
    channel.setMethodCallHandler(null);
    try {
      await channel.invokeMethod('update', {'active': false});
    } on MissingPluginException {
      /* Widget tests / non-Android. */
    }
  }
}
