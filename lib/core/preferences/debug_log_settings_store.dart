import 'package:flutter/services.dart';

import '../diagnostics/app_log.dart';

/// 调试日志开关保存在 Android 应用私有设置中，不包含任何日志内容。
class DebugLogSettingsStore {
  static const channel = MethodChannel('dev.dawnmesh.intercom/preferences');

  Future<bool> load() async {
    try {
      return await channel.invokeMethod<bool>('getDebugLoggingEnabled') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> save(bool enabled) async {
    try {
      await channel.invokeMethod<void>('setDebugLoggingEnabled', {
        'enabled': enabled,
      });
      return true;
    } on MissingPluginException {
      // Widget tests and non-Android hosts have no private preference plugin.
      return true;
    } on PlatformException catch (error) {
      AppLog.warn('设置', '调试日志开关保存失败', error);
      return false;
    }
  }
}
