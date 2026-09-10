import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dawn_mesh/core/diagnostics/app_log.dart';
import 'package:dawn_mesh/core/platform/native_debug_log_channel.dart';
import 'package:dawn_mesh/core/preferences/audio_tuning_settings_store.dart';
import 'package:dawn_mesh/core/preferences/debug_log_settings_store.dart';
import 'package:dawn_mesh/ui/pages/debug_log_page.dart';

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
    final controlCalls = <MethodCall>[];
    final audioCalls = <MethodCall>[];
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
    messenger.setMockMethodCallHandler(NativeDebugLogChannel.control, (
      call,
    ) async {
      controlCalls.add(call);
      return true;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        NativeDebugLogChannel.control,
        null,
      ),
    );
    messenger.setMockMethodCallHandler(AudioTuningSettingsStore.audioChannel, (
      call,
    ) async {
      audioCalls.add(call);
      return true;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        AudioTuningSettingsStore.audioChannel,
        null,
      ),
    );
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: DebugLogPage(isNight: true)),
    );
    expect(find.text('Debug logs'), findsOneWidget);
    expect(find.text('Off'), findsWidgets);
    expect(find.text('Fast'), findsOneWidget);
    expect(find.text('Balanced'), findsOneWidget);
    expect(find.text('Stable'), findsOneWidget);
    expect(AppLog.isEnabled, isFalse);

    await tester.tap(find.text('Fast'));
    await tester.pumpAndSettle();
    expect(
      calls.where((call) => call.method == 'setAudioTuningProfile').single.arguments,
      {'profile': 'low'},
    );
    expect(audioCalls.single.arguments, {'profile': 'low'});

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(AppLog.isEnabled, isTrue);
    expect(
      calls.where((call) => call.method == 'setDebugLoggingEnabled').single.method,
      'setDebugLoggingEnabled',
    );
    expect(controlCalls.single.method, 'captureSystemSnapshot');

    await tester.tap(find.byIcon(Icons.memory_rounded));
    await tester.pump();
    expect(controlCalls, hasLength(2));

    AppLog.warn('蓝牙', '链路出现波动');
    AppLog.info('音频', '缓冲恢复正常');
    await tester.pumpAndSettle();
    expect(find.textContaining('缓冲恢复正常'), findsOneWidget);
    expect(AppLog.recent.any((entry) => entry.message == '链路出现波动'), isTrue);

    await tester.tap(find.widgetWithText(ChoiceChip, 'WARN'));
    await tester.pump();
    expect(find.textContaining('链路出现波动'), findsOneWidget);
    expect(find.textContaining('缓冲恢复正常'), findsNothing);

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
