import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/preferences/debug_log_settings_store.dart';
import 'package:sunset_ripple/core/preferences/nickname_store.dart';

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
}
