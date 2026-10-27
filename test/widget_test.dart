import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dawn_mesh/main.dart';
import 'package:dawn_mesh/ui/widgets/celestial_canvas.dart';

void main() {
  const audioChannel = MethodChannel('dev.dawnmesh.intercom/audio');
  const audioEventsChannel = MethodChannel(
    'dev.dawnmesh.intercom/audio_events',
  );
  const wifiDirectChannel = MethodChannel('dev.dawnmesh.intercom/wifi_direct');
  const wifiDirectEventsChannel = MethodChannel(
    'dev.dawnmesh.intercom/wifi_direct_events',
  );

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(audioChannel, (_) async => null);
    messenger.setMockMethodCallHandler(audioEventsChannel, (_) async => null);
    messenger.setMockMethodCallHandler(wifiDirectChannel, (call) async {
      if (call.method == 'isSupported') return true;
      if (call.method == 'isEnabled') return true;
      if (call.method == 'discoverPeers') return true;
      return null;
    });
    messenger.setMockMethodCallHandler(
      wifiDirectEventsChannel,
      (_) async => null,
    );
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(audioChannel, null);
    messenger.setMockMethodCallHandler(audioEventsChannel, null);
    messenger.setMockMethodCallHandler(wifiDirectChannel, null);
    messenger.setMockMethodCallHandler(wifiDirectEventsChannel, null);
  });

  // 首页 initState 会发起一次扫描，里面有 2 秒的 Future.delayed；
  // 不把假时钟推过去，测试结束时会因为「还有未完成的 Timer」而失败。
  const scanSettle = Duration(seconds: 3);

  for (final locale in [const Locale('zh'), const Locale('en')]) {
    for (final night in [false, true]) {
      for (final layout in [
        (size: const Size(320, 640), scale: 1.0, top: 24.0),
        (size: const Size(320, 640), scale: 2.0, top: 24.0),
        (size: const Size(360, 640), scale: 2.0, top: 24.0),
        (size: const Size(390, 844), scale: 1.0, top: 59.0),
      ]) {
        testWidgets('首页晨光布局 ${locale.languageCode} $night $layout', (
          tester,
        ) async {
          tester.view.physicalSize = layout.size;
          tester.view.devicePixelRatio = 1;
          tester.view.padding = FakeViewPadding(top: layout.top);
          tester.platformDispatcher.localesTestValue = [locale];
          tester.platformDispatcher.platformBrightnessTestValue = night
              ? Brightness.dark
              : Brightness.light;
          tester.platformDispatcher.textScaleFactorTestValue = layout.scale;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearAllTestValues);
          await tester.pumpWidget(const DawnMeshApp());
          await tester.pump(scanSettle);
          expect(tester.takeException(), isNull);
          final canvasFinder = find.byType(CelestialCanvas);
          final canvas = tester.widget<CelestialCanvas>(canvasFinder);
          final bounds = tester.getRect(canvasFinder);
          final sunLeft =
              bounds.left +
              bounds.width * canvas.celestialCenterFactorX -
              canvas.celestialRadius;
          final title = find.text(
            locale.languageCode == 'zh' ? '曙光之声' : 'DawnMesh',
          );
          final caption = find.text(
            locale.languageCode == 'zh'
                ? '越过地平线，让声音相遇。'
                : 'Beyond the horizon, let voices meet.',
          );
          expect(tester.getRect(title).right, lessThan(sunLeft));
          expect(tester.getRect(caption).right, lessThan(sunLeft));
          expect(
            tester.getRect(caption).bottom,
            lessThanOrEqualTo(bounds.bottom),
          );
          final settings = tester.getRect(
            find.byKey(const ValueKey('room-settings-button')),
          );
          expect(settings.top, greaterThanOrEqualTo(layout.top));
          final settingsIcon = tester.getRect(
            find.byIcon(Icons.settings_outlined),
          );
          final sunCenter = Offset(
            bounds.left + bounds.width * canvas.celestialCenterFactorX,
            bounds.top + bounds.height * canvas.celestialCenterFactorY,
          );
          final closestIconPoint = Offset(
            sunCenter.dx.clamp(settingsIcon.left, settingsIcon.right),
            sunCenter.dy.clamp(settingsIcon.top, settingsIcon.bottom),
          );
          expect(
            (sunCenter - closestIconPoint).distance,
            greaterThan(canvas.celestialRadius + 2),
          );
          await tester.pumpWidget(const SizedBox());
          await tester.pump(scanSettle);
        });
      }
    }
  }

  testWidgets('首页能正常渲染并显示输入框与建房按钮', (WidgetTester tester) async {
    await tester.pumpWidget(const DawnMeshApp());
    await tester.pump(scanSettle);

    // 能找到标题（DawnMesh 或 曙光之声）与输入框
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data == '曙光之声' || w.data == 'DawnMesh'),
      ),
      findsWidgets,
    );
    expect(find.byType(TextField), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data == '创建 Wi-Fi 房间' || w.data == 'Create Wi-Fi room'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('可以在 WiFi 房与蓝牙房之间切换', (WidgetTester tester) async {
    await tester.pumpWidget(const DawnMeshApp());
    await tester.pump(scanSettle);

    final bluetoothChip = find.byWidgetPredicate(
      (w) => w is Text && (w.data == '蓝牙房间' || w.data == 'Bluetooth room'),
    );
    expect(bluetoothChip, findsOneWidget);

    await tester.tap(bluetoothChip);
    // 切换房型会重新扫描，同样有 2 秒延时。
    await tester.pump();
    await tester.pump(scanSettle);

    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data == '创建蓝牙房间' || w.data == 'Create Bluetooth room'),
      ),
      findsOneWidget,
    );
  });
  testWidgets('首页只有设置入口，外观和离线转交收进设置页', (tester) async {
    await tester.pumpWidget(const DawnMeshApp());
    await tester.pump(scanSettle);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(find.byIcon(Icons.mark_email_unread_outlined), findsNothing);
    expect(find.byIcon(Icons.terminal_rounded), findsNothing);
    await tester.tap(find.byKey(const ValueKey('room-settings-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-courier')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-debug')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('appearance-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();
    final settings = tester.element(
      find.byKey(const ValueKey('appearance-mode')),
    );
    expect(Theme.of(settings).brightness, Brightness.dark);
    expect(tester.takeException(), isNull);
  });
}
