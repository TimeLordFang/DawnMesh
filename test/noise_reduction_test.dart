import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dawn_mesh/core/audio/noise_reduction.dart';
import 'package:dawn_mesh/ui/widgets/noise_reduction_control.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.dawnmesh.intercom/audio');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    NoiseReductionSettings.level.value = NoiseReductionLevel.standard;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'getNoiseReduction' ? 2 : null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('loads saved level and attaches/detaches internet processor', () async {
    await NoiseReductionSettings.load();
    expect(NoiseReductionSettings.level.value, NoiseReductionLevel.strong);
    await NoiseReductionSettings.startInternet();
    await NoiseReductionSettings.stopInternet();
    expect(calls.map((call) => call.method), [
      'getNoiseReduction',
      'startInternetNoiseReduction',
      'stopInternetNoiseReduction',
    ]);
  });

  test('failed native change keeps the previously displayed level', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: 'failed'),
        );
    await expectLater(
      NoiseReductionSettings.setLevel(NoiseReductionLevel.off),
      throwsA(isA<PlatformException>()),
    );
    expect(NoiseReductionSettings.level.value, NoiseReductionLevel.standard);
  });

  testWidgets('room control offers all levels and applies the selected value', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: NoiseReductionControl(isNight: false)),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('noise-reduction-control')));
    await tester.pumpAndSettle();
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('Strong'), findsOneWidget);
    await tester.tap(find.text('Strong'));
    await tester.pumpAndSettle();
    expect(NoiseReductionSettings.level.value, NoiseReductionLevel.strong);
    expect(calls.single.method, 'setNoiseReduction');
    expect(calls.single.arguments, {'level': 2});
    expect(tester.takeException(), isNull);
  });
}
