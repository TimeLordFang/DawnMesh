import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dawn_mesh/ui/widgets/room_invite_row.dart';

void main() {
  Widget panel({String code = '012345', bool visible = true}) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 280,
        child: RoomInviteRow(code: code, initiallyVisible: visible),
      ),
    ),
  );

  testWidgets(
    'invite hides after ten seconds and each reveal starts a fresh timer',
    (tester) async {
      await tester.pumpWidget(panel());
      expect(find.text('012345'), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      expect(find.text('012345'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('012345'), findsNothing);
      expect(find.text('••••••'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();
      expect(find.text('012345'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pump();
      expect(find.text('012345'), findsNothing);
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('012345'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('012345'), findsNothing);
    },
  );

  testWidgets(
    'background hides immediately and resume never exposes the code',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(panel());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('012345'), findsNothing);
      expect(find.bySemanticsLabel('邀请码已隐藏'), findsOneWidget);
      expect(find.bySemanticsLabel('邀请码 0 1 2 3 4 5'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('012345'), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets('room change replaces the code and disposal cancels timers', (
    tester,
  ) async {
    await tester.pumpWidget(panel());
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpWidget(panel(code: '654321'));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('654321'), findsOneWidget);
    expect(find.text('012345'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 15));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'member starts hidden and row fits compact screen at large text scale',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(panel(visible: false));
      expect(find.text('012345'), findsNothing);
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();
      expect(find.text('012345'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('invite follows host role and is removed from the former host', (
    tester,
  ) async {
    final isHost = ValueNotifier(false);
    addTearDown(isHost.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: isHost,
          builder: (context, value, _) =>
              HostRoomInviteRow(isHost: value, code: '012345'),
        ),
      ),
    );
    expect(find.text('012345'), findsNothing);

    isHost.value = true;
    await tester.pump();
    expect(find.text('012345'), findsOneWidget);

    isHost.value = false;
    await tester.pump();
    expect(find.text('012345'), findsNothing);
    expect(find.byIcon(Icons.visibility_outlined), findsNothing);

    isHost.value = true;
    await tester.pump();
    expect(find.text('012345'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
