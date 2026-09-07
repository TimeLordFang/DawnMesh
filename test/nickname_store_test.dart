import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
