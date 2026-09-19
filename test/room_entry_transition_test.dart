import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dawn_mesh/ui/pages/session_stage.dart';
import 'package:dawn_mesh/ui/widgets/room_invite_row.dart';

/// 进房转场的端到端验收：点「创建 WiFi 房」之后，首页那组 UI 要走干净，
/// 房间那组要到齐，中途每一帧都不许溢出；返回时再原路退回首页。
void main() {
  const audioChannel = MethodChannel('dev.dawnmesh.intercom/audio');
  const audioEventsChannel = MethodChannel(
    'dev.dawnmesh.intercom/audio_events',
  );

  setUp(() {
    // 单测里没有平台侧实现，把音频通道打桩掉，否则 MissingPluginException
    // 会盖住真正要看的布局问题。
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(audioChannel, (_) async => null);
    messenger.setMockMethodCallHandler(audioEventsChannel, (_) async => null);
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(audioChannel, null);
    messenger.setMockMethodCallHandler(audioEventsChannel, null);
  });

  Finder findTitle() => find.byWidgetPredicate(
    (w) => w is Text && (w.data == '曙光之声' || w.data == 'DawnMesh'),
  );
  Finder findCreateWifi() => find.byWidgetPredicate(
    (w) =>
        w is Text && (w.data == '创建 Wi-Fi 房间' || w.data == 'Create Wi-Fi room'),
  );
  Finder findInCall() => find.byKey(const ValueKey('automatic-talk-status'));
  Finder findHangUp() => find.byWidgetPredicate(
    (w) => w is Text && (w.data == '挂断' || w.data == 'Hang up'),
  );
  Finder findRoomTitle() => find.byWidgetPredicate(
    (w) =>
        w is Text &&
        (w.data?.endsWith('的聊天室 · Wi-Fi') == true ||
            w.data?.endsWith("'s chat · Wi-Fi") == true),
  );

  // Native-channel futures and real loopback sockets need both event loops.
  // Await observable room state instead of assuming one 500 ms sleep completes
  // every asynchronous permission/scan/socket step.
  Future<void> waitForRoom(WidgetTester tester, bool inRoom) async {
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      expect(tester.takeException(), isNull);
      if (findInCall().evaluate().isNotEmpty == inRoom) return;
    }
    fail('Room transition did not complete');
  }

  testWidgets('创建房间：首页 UI 离场、背景留场、房间 UI 入场', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: SessionStage(isNight: false, onToggleTheme: () {})),
    );
    // 首页 initState 会发起扫描，里面有 2 秒的 Future.delayed。
    await tester.pump(const Duration(seconds: 3));

    expect(findTitle(), findsWidgets);
    expect(findInCall(), findsNothing);

    // createRoom 里有真实的 socket 绑定，得让真事件循环跑一轮。
    await tester.runAsync(() async {
      await tester.tap(findCreateWifi());
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await waitForRoom(tester, true);
    await tester.pump();

    // 逐帧走完整段转场，任何一帧溢出都会在这里冒出来。
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull, reason: '转场第 ${i + 1} 帧溢出');
    }

    // 落位：首页那组走干净了，房间那组到齐了。
    expect(findTitle(), findsNothing);
    expect(findCreateWifi(), findsNothing);
    expect(findInCall(), findsOneWidget);
    expect(findHangUp(), findsOneWidget);
    expect(findRoomTitle(), findsOneWidget);
    final inviteRow = find.byType(RoomInviteRow);
    expect(inviteRow, findsOneWidget);
    final code = tester.widget<RoomInviteRow>(inviteRow).code;
    expect(RegExp(r'^\d{6}$').hasMatch(code), isTrue);
    expect(find.text(code), findsOneWidget);
    expect(
      tester.getTopLeft(inviteRow).dy,
      greaterThan(tester.getBottomLeft(findRoomTitle()).dy),
    );
    await tester.pump(const Duration(seconds: 10));
    expect(find.text(code), findsNothing);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(find.text(code), findsOneWidget);

    // 离开房间完成清理
    await tester.tap(findHangUp());
    await tester.pump();
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // 等待会话和 TCP 监听端口真正释放，避免下一个用例立即
    // 建房时与上一个异步 dispose 抢占同一端口。
    await waitForRoom(tester, false);
  });

  testWidgets('离开房间：原路退回首页', (tester) async {
    tester.view.physicalSize = const Size(411, 892);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: SessionStage(isNight: false, onToggleTheme: () {})),
    );
    await tester.pump(const Duration(seconds: 3));

    await tester.runAsync(() async {
      await tester.tap(findCreateWifi());
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await waitForRoom(tester, true);
    await tester.pump();
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(findInCall(), findsOneWidget);

    // 退场清理
    await tester.tap(findHangUp());
    await tester.pump();
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull, reason: '退场第 ${i + 1} 帧溢出');
    }

    await waitForRoom(tester, false);
    expect(findInCall(), findsNothing);
    expect(findTitle(), findsWidgets);
    expect(findCreateWifi(), findsOneWidget);

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
  });

  testWidgets('返回首页保持通话，并可从当前房间卡片重新进入', (tester) async {
    tester.view.physicalSize = const Size(411, 892);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: SessionStage(isNight: false, onToggleTheme: () {})),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.runAsync(() async {
      await tester.tap(findCreateWifi());
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await waitForRoom(tester, true);
    await tester.pump(const Duration(seconds: 2));

    final inviteRow = find.byType(RoomInviteRow);
    final invite = tester.widget<RoomInviteRow>(inviteRow).code;

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const ValueKey('active-room-card')), findsOneWidget);
    expect(findCreateWifi(), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('active-room-card')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(findInCall(), findsOneWidget);
    expect(
      tester.widget<RoomInviteRow>(find.byType(RoomInviteRow)).code,
      invite,
    );

    await tester.tap(findHangUp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await waitForRoom(tester, false);
    expect(find.byKey(const ValueKey('active-room-card')), findsNothing);
  });
}
