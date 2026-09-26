import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Additional offline voice enhancement. Platform echo cancellation and baseline
/// noise processing remain enabled even when this enhancement is off.
enum NoiseReductionLevel { off, standard, strong }

class NoiseReductionSettings {
  static const _channel = MethodChannel('dev.dawnmesh.intercom/audio');
  static final level = ValueNotifier(NoiseReductionLevel.standard);

  static Future<void> load() async {
    try {
      final saved = await _channel.invokeMethod<int>('getNoiseReduction');
      if (saved != null &&
          saved >= 0 &&
          saved < NoiseReductionLevel.values.length) {
        level.value = NoiseReductionLevel.values[saved];
      }
    } on MissingPluginException {
      // Widget tests and non-Android previews have no native audio plugin.
    }
  }

  static Future<void> setLevel(NoiseReductionLevel next) async {
    await _channel.invokeMethod<void>('setNoiseReduction', {
      'level': next.index,
    });
    level.value = next;
  }

  static Future<void> startInternet() async {
    try {
      await _channel.invokeMethod<void>('startInternetNoiseReduction');
    } on MissingPluginException {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) rethrow;
    }
  }

  static Future<void> stopInternet() async {
    try {
      await _channel.invokeMethod<void>('stopInternetNoiseReduction');
    } on MissingPluginException {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) rethrow;
    }
  }
}
