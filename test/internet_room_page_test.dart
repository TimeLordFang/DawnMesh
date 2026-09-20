import 'package:dawn_mesh/core/internet/internet_models.dart';
import 'package:dawn_mesh/core/internet/internet_room_api.dart';
import 'package:dawn_mesh/core/internet/internet_room_session.dart';
import 'package:dawn_mesh/ui/pages/internet_room_page.dart';
import 'package:dawn_mesh/ui/pages/internet_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  InternetRoomSession makeSession({bool isHost = false}) {
    const profile = ServerProfile(
      id: 'server-test',
      name: '测试服务器',
      baseUrl: 'https://talk.example.test',
    );
    return InternetRoomSession.forTesting(
      api: InternetRoomApi(profile),
      profile: profile,
      nickname: '成员',
      roomId: 'room-test',
      memberId: 'member-test',
      summary: const InternetRoomSummary(
        id: 'room-test',
        name: '测试房间',
        memberCount: 2,
        maxParticipants: 25,
        hostNickname: '群主',
      ),
      isHost: isHost,
    );
  }

  testWidgets(
    'a dissolved room notifies the member and returns after ten seconds',
    (tester) async {
      final session = makeSession();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          InternetRoomPage(session: session, isNight: false),
                    ),
                  ),
                  child: const Text('房间列表'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('房间列表'));
      await tester.pumpAndSettle();

      await session.receiveRoomEndedForTesting();
      await tester.pump();
      expect(find.text('房间已被群主解散，10 秒后自动返回房间列表'), findsOneWidget);
      expect(find.text('10 秒后自动返回房间列表'), findsOneWidget);

      await tester.pump(const Duration(seconds: 9));
      expect(find.byType(InternetRoomPage), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.byType(InternetRoomPage), findsNothing);
      expect(find.text('房间列表'), findsOneWidget);
    },
  );

  testWidgets('incoming chat shows a badge and opening chat clears it', (
    tester,
  ) async {
    final session = makeSession();
    addTearDown(session.disposeSession);
    await tester.pumpWidget(
      MaterialApp(home: InternetRoomPage(session: session, isNight: false)),
    );

    session.receiveChatForTesting(text: '有新消息');
    await tester.pump();

    expect(session.unreadChatCount, 1);
    expect(find.byKey(const ValueKey('chat-unread-dot')), findsOneWidget);
    expect(find.byKey(const ValueKey('room-chat-dock')), findsOneWidget);
    expect(find.text('有新消息'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-chat-history')));
    await tester.pump();

    expect(session.unreadChatCount, 0);
    expect(find.text('有新消息'), findsWidgets);
  });

  testWidgets('host does not see the dissolved-by-owner countdown', (
    tester,
  ) async {
    final session = makeSession(isHost: true);
    addTearDown(session.disposeSession);
    await tester.pumpWidget(
      MaterialApp(home: InternetRoomPage(session: session, isNight: false)),
    );

    await session.receiveRoomEndedForTesting();
    await tester.pump();

    expect(find.text('房间已被群主解散，10 秒后自动返回房间列表'), findsNothing);
  });

  testWidgets('room back opens network list and the next back opens app home', (
    tester,
  ) async {
    final session = makeSession();
    InternetRoomSession? retained = session;
    addTearDown(session.disposeSession);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InternetHomePage(
                      isNight: false,
                      nickname: '成员',
                      activeSession: retained,
                      reopenActiveRoom: true,
                      onActiveSessionChanged: (value) => retained = value,
                    ),
                  ),
                ),
                child: const Text('App 主界面'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('App 主界面'));
    await tester.pumpAndSettle();
    expect(find.byType(InternetRoomPage), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(InternetHomePage), findsOneWidget);
    expect(find.byType(InternetRoomPage), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(InternetHomePage), findsNothing);
    expect(find.text('App 主界面'), findsOneWidget);
    expect(retained, same(session));
  });

  testWidgets(
    'public-room dock opens full chat and back closes keyboard first',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = makeSession();
      addTearDown(session.disposeSession);
      session.receiveChatForTesting(text: '公网房间里的一条长消息，键盘弹出后仍应尽量显示内容并保留输入框。');

      await tester.pumpWidget(
        MaterialApp(home: InternetRoomPage(session: session, isNight: false)),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final dockInput = find.byKey(const ValueKey('room-chat-input'));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('room-chat-dock'))).dx,
        closeTo(18, 0.1),
      );
      await tester.tap(dockInput);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final fullInput = find.byKey(const ValueKey('full-chat-input'));
      expect(fullInput, findsOneWidget);
      final inputFocusNode = tester
          .widget<EditableText>(
            find.descendant(of: fullInput, matching: find.byType(EditableText)),
          )
          .focusNode;
      expect(inputFocusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pump();
      tester.view.resetViewInsets();
      await tester.pump();

      expect(fullInput, findsOneWidget, reason: '第一次返回只应收起输入法，不能关闭聊天或退出房间');
      expect(find.byType(InternetRoomPage), findsOneWidget);
      expect(inputFocusNode.hasFocus, isFalse);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(fullInput, findsNothing);
      expect(find.byType(InternetRoomPage), findsOneWidget);
      expect(dockInput, findsOneWidget);
    },
  );
}
