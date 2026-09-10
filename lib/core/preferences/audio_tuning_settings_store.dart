import 'package:flutter/services.dart';

import '../diagnostics/app_log.dart';

enum AudioTuningProfile {
  lowLatency('low'),
  balanced('balanced'),
  stable('stable');

  const AudioTuningProfile(this.wireName);
  final String wireName;

  static AudioTuningProfile fromWireName(String? value) {
    for (final profile in values) {
      if (profile.wireName == value) return profile;
    }
    return balanced;
  }
}

/// 音频调优档位保存在 Android 私有设置中，并同步到正在运行的原生音频管线。
class AudioTuningSettingsStore {
  static const preferencesChannel = MethodChannel(
    'dev.dawnmesh.intercom/preferences',
  );
  static const audioChannel = MethodChannel('dev.dawnmesh.intercom/audio');

  Future<AudioTuningProfile> load() async {
    try {
      final value = await preferencesChannel.invokeMethod<String>(
        'getAudioTuningProfile',
      );
      return AudioTuningProfile.fromWireName(value);
    } on MissingPluginException {
      return AudioTuningProfile.balanced;
    } on PlatformException {
      return AudioTuningProfile.balanced;
    }
  }

  Future<bool> save(AudioTuningProfile profile) async {
    try {
      await preferencesChannel.invokeMethod<void>('setAudioTuningProfile', {
        'profile': profile.wireName,
      });
    } on MissingPluginException {
      // Widget tests and non-Android hosts have no private preference plugin.
    } on PlatformException catch (error) {
      AppLog.warn('设置', '音频调优档位保存失败', error);
      return false;
    }

    try {
      await audioChannel.invokeMethod<void>('setAudioTuningProfile', {
        'profile': profile.wireName,
      });
    } on MissingPluginException {
      // Non-Android hosts have no native audio pipeline.
    } on PlatformException catch (error) {
      // 设置已持久化，下次创建音频管线仍会使用；只记录本次热更新失败。
      AppLog.warn('设置', '音频调优档位将在下次进入房间时生效', error);
    }
    return true;
  }
}
