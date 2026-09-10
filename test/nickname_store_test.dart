import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dawn_mesh/core/preferences/audio_tuning_settings_store.dart';
import 'package:dawn_mesh/core/preferences/debug_log_settings_store.dart';
import 'package:dawn_mesh/core/preferences/nickname_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.dawnmesh.intercom/preferences');

  test(
    'nickname is saved and restored through private app preferences',
    () async {
      String? saved;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'setNickname') {
          saved = (call.arguments as Map)['nickname'] as String;
          return null;
        }
        if (call.method == 'getNickname') return saved;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final store = NicknameStore();
      await store.save('红米用户');
      expect(await store.load(), '红米用户');
    },
  );

  test('debug logging preference is loaded and saved privately', () async {
    var enabled = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setDebugLoggingEnabled') {
        enabled = (call.arguments as Map)['enabled'] as bool;
        return null;
      }
      if (call.method == 'getDebugLoggingEnabled') return enabled;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final store = DebugLogSettingsStore();
    expect(await store.load(), isFalse);
    expect(await store.save(true), isTrue);
    expect(await store.load(), isTrue);
  });

  test('audio tuning profile is saved, restored and applied to native audio', () async {
    String? saved;
    final audioCalls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setAudioTuningProfile') {
        saved = (call.arguments as Map)['profile'] as String;
        return null;
      }
      if (call.method == 'getAudioTuningProfile') return saved;
      return null;
    });
    messenger.setMockMethodCallHandler(AudioTuningSettingsStore.audioChannel, (
      call,
    ) async {
      audioCalls.add(call);
      return true;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(
        AudioTuningSettingsStore.audioChannel,
        null,
      );
    });

    final store = AudioTuningSettingsStore();
    expect(await store.load(), AudioTuningProfile.balanced);
    expect(await store.save(AudioTuningProfile.lowLatency), isTrue);
    expect(await store.load(), AudioTuningProfile.lowLatency);
    expect(audioCalls.single.method, 'setAudioTuningProfile');
    expect(audioCalls.single.arguments, {'profile': 'low'});
  });

  test('advanced audio parameters round-trip and apply without a rebuild', () async {
    Map<Object?, Object?>? saved;
    final audioCalls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setAudioTuningParameters') {
        saved = Map<Object?, Object?>.from(call.arguments as Map);
        return saved;
      }
      if (call.method == 'getAudioTuningParameters') return saved;
      return null;
    });
    messenger.setMockMethodCallHandler(AudioTuningSettingsStore.audioChannel, (
      call,
    ) async {
      audioCalls.add(call);
      return true;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(
        AudioTuningSettingsStore.audioChannel,
        null,
      );
    });

    final store = AudioTuningSettingsStore();
    final custom = AudioTuningParameters.defaults(AudioTuningProfile.balanced)
        .copyWith(
          headsetBitrate: 6000,
          l2capCoalesceMillis: 20,
          flushEveryWrite: false,
          dropStaleRealtime: true,
          maxRealtimeAgeMillis: 40,
        );
    expect(await store.saveParameters(custom), isTrue);
    final restored = await store.loadParameters();

    expect(restored.headsetBitrate, 6000);
    expect(restored.l2capCoalesceMillis, 20);
    expect(restored.flushEveryWrite, isFalse);
    expect(restored.dropStaleRealtime, isTrue);
    expect(audioCalls.single.method, 'setAudioTuningParameters');
  });
}
