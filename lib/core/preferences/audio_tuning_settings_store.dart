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

class AudioTuningParameters {
  const AudioTuningParameters({
    required this.profile,
    required this.prebufferFrames,
    required this.maxBufferFrames,
    required this.maxAdaptiveFrames,
    required this.maxPlayoutQueueFrames,
    required this.stableFramesBeforeDecay,
    required this.maxConcealmentFrames,
    required this.audioTrackBufferFrames,
    required this.l2capCoalesceMillis,
    required this.headsetBitrate,
    required this.dropStaleRealtime,
    required this.maxRealtimeAgeMillis,
    required this.flushEveryWrite,
  });

  final AudioTuningProfile profile;
  final int prebufferFrames;
  final int maxBufferFrames;
  final int maxAdaptiveFrames;
  final int maxPlayoutQueueFrames;
  final int stableFramesBeforeDecay;
  final int maxConcealmentFrames;
  final int audioTrackBufferFrames;
  final int l2capCoalesceMillis;
  final int headsetBitrate;
  final bool dropStaleRealtime;
  final int maxRealtimeAgeMillis;
  final bool flushEveryWrite;

  static AudioTuningParameters defaults(AudioTuningProfile profile) =>
      switch (profile) {
        AudioTuningProfile.lowLatency => const AudioTuningParameters(
          profile: AudioTuningProfile.lowLatency,
          prebufferFrames: 2,
          maxBufferFrames: 8,
          maxAdaptiveFrames: 4,
          maxPlayoutQueueFrames: 3,
          stableFramesBeforeDecay: 25,
          maxConcealmentFrames: 2,
          audioTrackBufferFrames: 1,
          l2capCoalesceMillis: 0,
          headsetBitrate: 8000,
          dropStaleRealtime: true,
          maxRealtimeAgeMillis: 60,
          flushEveryWrite: true,
        ),
        AudioTuningProfile.balanced => const AudioTuningParameters(
          profile: AudioTuningProfile.balanced,
          prebufferFrames: 6,
          maxBufferFrames: 24,
          maxAdaptiveFrames: 14,
          maxPlayoutQueueFrames: 24,
          stableFramesBeforeDecay: 100,
          maxConcealmentFrames: 2,
          audioTrackBufferFrames: 4,
          l2capCoalesceMillis: 50,
          headsetBitrate: 6000,
          dropStaleRealtime: true,
          maxRealtimeAgeMillis: 180,
          flushEveryWrite: true,
        ),
        AudioTuningProfile.stable => const AudioTuningParameters(
          profile: AudioTuningProfile.stable,
          prebufferFrames: 10,
          maxBufferFrames: 32,
          maxAdaptiveFrames: 24,
          maxPlayoutQueueFrames: 32,
          stableFramesBeforeDecay: 250,
          maxConcealmentFrames: 3,
          audioTrackBufferFrames: 6,
          l2capCoalesceMillis: 60,
          headsetBitrate: 8000,
          dropStaleRealtime: true,
          maxRealtimeAgeMillis: 260,
          flushEveryWrite: true,
        ),
      };

  factory AudioTuningParameters.fromMap(
    Map<Object?, Object?> raw, {
    AudioTuningParameters? fallback,
  }) {
    final profile = AudioTuningProfile.fromWireName(raw['profile'] as String?);
    final base = fallback ?? defaults(profile);
    int number(String key, int value) => (raw[key] as num?)?.round() ?? value;
    final prebuffer = number(
      'prebufferFrames',
      base.prebufferFrames,
    ).clamp(1, 15);
    final adaptive = number(
      'maxAdaptiveFrames',
      base.maxAdaptiveFrames,
    ).clamp(prebuffer, 30);
    final playout = number(
      'maxPlayoutQueueFrames',
      base.maxPlayoutQueueFrames,
    ).clamp(1, 32);
    final minimumBuffer = [
      prebuffer,
      adaptive,
      playout,
    ].reduce((a, b) => a > b ? a : b);
    final maxBuffer = number(
      'maxBufferFrames',
      base.maxBufferFrames,
    ).clamp(minimumBuffer, 32);
    return AudioTuningParameters(
      profile: profile,
      prebufferFrames: prebuffer,
      maxBufferFrames: maxBuffer,
      maxAdaptiveFrames: adaptive.clamp(prebuffer, maxBuffer),
      maxPlayoutQueueFrames: playout.clamp(1, maxBuffer),
      stableFramesBeforeDecay: number(
        'stableFramesBeforeDecay',
        base.stableFramesBeforeDecay,
      ).clamp(10, 500),
      maxConcealmentFrames: number(
        'maxConcealmentFrames',
        base.maxConcealmentFrames,
      ).clamp(0, 5),
      audioTrackBufferFrames: number(
        'audioTrackBufferFrames',
        base.audioTrackBufferFrames,
      ).clamp(1, 12),
      l2capCoalesceMillis: number(
        'l2capCoalesceMillis',
        base.l2capCoalesceMillis,
      ).clamp(0, 100),
      headsetBitrate: number(
        'headsetBitrate',
        base.headsetBitrate,
      ).clamp(6000, 16000),
      dropStaleRealtime:
          raw['dropStaleRealtime'] as bool? ?? base.dropStaleRealtime,
      maxRealtimeAgeMillis: number(
        'maxRealtimeAgeMillis',
        base.maxRealtimeAgeMillis,
      ).clamp(20, 300),
      flushEveryWrite: raw['flushEveryWrite'] as bool? ?? base.flushEveryWrite,
    );
  }

  Map<String, Object> toMap() => {
    'profile': profile.wireName,
    'prebufferFrames': prebufferFrames,
    'maxBufferFrames': maxBufferFrames,
    'maxAdaptiveFrames': maxAdaptiveFrames,
    'maxPlayoutQueueFrames': maxPlayoutQueueFrames,
    'stableFramesBeforeDecay': stableFramesBeforeDecay,
    'maxConcealmentFrames': maxConcealmentFrames,
    'audioTrackBufferFrames': audioTrackBufferFrames,
    'l2capCoalesceMillis': l2capCoalesceMillis,
    'headsetBitrate': headsetBitrate,
    'dropStaleRealtime': dropStaleRealtime,
    'maxRealtimeAgeMillis': maxRealtimeAgeMillis,
    'flushEveryWrite': flushEveryWrite,
  };

  AudioTuningParameters copyWith({
    int? prebufferFrames,
    int? maxBufferFrames,
    int? maxAdaptiveFrames,
    int? maxPlayoutQueueFrames,
    int? stableFramesBeforeDecay,
    int? maxConcealmentFrames,
    int? audioTrackBufferFrames,
    int? l2capCoalesceMillis,
    int? headsetBitrate,
    bool? dropStaleRealtime,
    int? maxRealtimeAgeMillis,
    bool? flushEveryWrite,
  }) {
    final prebuffer = prebufferFrames ?? this.prebufferFrames;
    final adaptive = maxAdaptiveFrames ?? this.maxAdaptiveFrames;
    final playout = maxPlayoutQueueFrames ?? this.maxPlayoutQueueFrames;
    final requestedMaxBuffer = maxBufferFrames ?? this.maxBufferFrames;
    final maxBuffer = [
      prebuffer,
      adaptive,
      playout,
      requestedMaxBuffer,
    ].reduce((a, b) => a > b ? a : b).clamp(1, 32);
    return AudioTuningParameters(
      profile: profile,
      prebufferFrames: prebuffer.clamp(1, 15),
      maxBufferFrames: maxBuffer,
      maxAdaptiveFrames: adaptive.clamp(prebuffer, maxBuffer),
      maxPlayoutQueueFrames: playout.clamp(1, maxBuffer),
      stableFramesBeforeDecay:
          stableFramesBeforeDecay ?? this.stableFramesBeforeDecay,
      maxConcealmentFrames: maxConcealmentFrames ?? this.maxConcealmentFrames,
      audioTrackBufferFrames:
          audioTrackBufferFrames ?? this.audioTrackBufferFrames,
      l2capCoalesceMillis: l2capCoalesceMillis ?? this.l2capCoalesceMillis,
      headsetBitrate: headsetBitrate ?? this.headsetBitrate,
      dropStaleRealtime: dropStaleRealtime ?? this.dropStaleRealtime,
      maxRealtimeAgeMillis: maxRealtimeAgeMillis ?? this.maxRealtimeAgeMillis,
      flushEveryWrite: flushEveryWrite ?? this.flushEveryWrite,
    );
  }
}

/// 参数保存在 Android 私有设置中，并同步到正在运行的原生音频和蓝牙管线。
class AudioTuningSettingsStore {
  static const preferencesChannel = MethodChannel(
    'dev.dawnmesh.intercom/preferences',
  );
  static const audioChannel = MethodChannel('dev.dawnmesh.intercom/audio');

  Future<AudioTuningProfile> load() async => (await loadParameters()).profile;

  Future<AudioTuningParameters> loadParameters() async {
    try {
      final raw = await preferencesChannel.invokeMethod<Map<Object?, Object?>>(
        'getAudioTuningParameters',
      );
      if (raw != null) return AudioTuningParameters.fromMap(raw);
      final legacy = await preferencesChannel.invokeMethod<String>(
        'getAudioTuningProfile',
      );
      return AudioTuningParameters.defaults(
        AudioTuningProfile.fromWireName(legacy),
      );
    } on MissingPluginException {
      // Widget tests and non-Android hosts use defaults.
    } on PlatformException catch (error) {
      AppLog.warn('设置', '读取音频调优参数失败', error);
    }
    return AudioTuningParameters.defaults(AudioTuningProfile.balanced);
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
    return _applyNative('setAudioTuningProfile', {'profile': profile.wireName});
  }

  Future<bool> saveParameters(AudioTuningParameters parameters) async {
    final values = parameters.toMap();
    try {
      await preferencesChannel.invokeMethod<void>(
        'setAudioTuningParameters',
        values,
      );
    } on MissingPluginException {
      // Widget tests and non-Android hosts have no private preference plugin.
    } on PlatformException catch (error) {
      AppLog.warn('设置', '音频调优参数保存失败', error);
      return false;
    }
    return _applyNative('setAudioTuningParameters', values);
  }

  Future<bool> _applyNative(String method, Map<String, Object> values) async {
    try {
      await audioChannel.invokeMethod<void>(method, values);
    } on MissingPluginException {
      // Non-Android hosts have no native audio pipeline.
    } on PlatformException catch (error) {
      AppLog.warn('设置', '音频参数将在下次进入房间时生效', error);
    }
    return true;
  }
}
