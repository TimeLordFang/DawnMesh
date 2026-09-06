import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/audio/audio_io.dart';
import 'package:sunset_ripple/core/session/room_session.dart';
import 'package:sunset_ripple/ui/pages/home_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('host.msknet.sunsetripple/ble_l2cap');
  const scanChannel = 'host.msknet.sunsetripple/ble_l2cap_scan';
  final calls = <MethodCall>[];
  bool advertisingWorks = true;
  RoomSession? entered;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    calls.clear();
    advertisingWorks = true;
    entered = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'startAdvertising') return advertisingWorks;
      return true;
    });
    for (final name in [
      scanChannel,
      'host.msknet.sunsetripple/ble_l2cap_data',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
    }
  });
  tearDown(() async {
    await entered?.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    for (final name in [
      scanChannel,
      'host.msknet.sunsetripple/ble_l2cap_data',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
  });

  Future<void> showHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeContent(
            isNight: false,
            stage: const AlwaysStoppedAnimation(0),
            audioIo: MockAudioIo(),
            onEnterRoom: (session, _) => entered = session,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('蓝牙对讲'));
    await tester.pump();
  }

  testWidgets(
    'BLE mode scans, renders a discovered room, and connects to its PSM',
    (tester) async {
      await showHome(tester);
      expect(calls.any((c) => c.method == 'startScan'), isTrue);
      messenger.handlePlatformMessage(
        scanChannel,
        const StandardMethodCodec().encodeSuccessEnvelope({
          'address': 'AA:BB:CC:DD:EE:FF',
          'psm': 129,
          'roomName': '测试蓝牙房',
          'memberCount': 1,
          'rssi': -40,
        }),
        (_) {},
      );
      await tester.pump();
      expect(find.text('测试蓝牙房'), findsOneWidget);
      await tester.tap(find.text('加入聊天'));
      await tester.pump();
      expect(
        calls.where((c) => c.method == 'connectL2cap').single.arguments['psm'],
        129,
      );
      expect(entered?.mode, RoomMode.bluetoothPtt);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets('advertising failure never enters a phantom room', (
    tester,
  ) async {
    advertisingWorks = false;
    await showHome(tester);
    await tester.tap(find.text('开始蓝牙对讲'));
    await tester.pump();
    expect(calls.any((c) => c.method == 'startAdvertising'), isTrue);
    expect(entered, isNull);
    expect(find.textContaining('蓝牙广播未能开启'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  });
}
