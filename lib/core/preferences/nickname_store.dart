import 'package:flutter/services.dart';
import '../diagnostics/app_log.dart';

class NicknameStore {
  static const channel = MethodChannel('dev.dawnmesh.intercom/preferences');

  Future<String?> load() async {
    try {
      return await channel.invokeMethod<String>('getNickname');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      AppLog.warn('设置', '无法读取已保存的昵称');
      return null;
    }
  }

  Future<void> save(String value) async {
    try {
      await channel.invokeMethod<void>('setNickname', {'nickname': value});
    } on MissingPluginException {
      // Android owns the private preference file; widget tests mock this channel.
    } on PlatformException {
      AppLog.warn('设置', '昵称保存失败，请检查设备存储空间');
    }
  }
}
