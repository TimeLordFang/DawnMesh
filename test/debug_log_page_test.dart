import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/diagnostics/app_log.dart';
import 'package:sunset_ripple/core/preferences/debug_log_settings_store.dart';
import 'package:sunset_ripple/ui/pages/debug_log_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLog.setEnabled(false);
    AppLog.clear();
  });

  tearDown(() {
    AppLog.setEnabled(false);
    AppLog.clear();
  });

  testWidgets('debug log page enables, displays, filters and clears logs', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(DebugLogSettingsStore.channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        DebugLogSettingsStore.channel,
        null,
      ),
    );
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: DebugLogPage(isNight: true)),
    );
    expect(find.text('Debug logs'), findsOneWidget);
    expect(find.text('Off'), findsWidgets);
    expect(AppLog.isEnabled, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(AppLog.isEnabled, isTrue);
    expect(calls.single.method, 'setDebugLoggingEnabled');

    AppLog.warn('蓝牙', '链路出现波动');
    AppLog.info('音频', '缓冲恢复正常');
    await tester.pumpAndSettle();
    expect(find.text('缓冲恢复正常'), findsOneWidget);
    expect(AppLog.recent.any((entry) => entry.message == '链路出现波动'), isTrue);

    await tester.tap(find.widgetWithText(ChoiceChip, 'WARN'));
    await tester.pump();
    expect(find.text('链路出现波动'), findsOneWidget);
    expect(find.text('缓冲恢复正常'), findsNothing);

    await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
    await tester.pump();
    expect(AppLog.recent, isEmpty);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(AppLog.isEnabled, isFalse);
    expect(calls.last.arguments, {'enabled': false});
    expect(tester.takeException(), isNull);
  });
}
