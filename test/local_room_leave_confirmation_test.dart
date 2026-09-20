import 'package:dawn_mesh/core/audio/audio_io.dart';
import 'package:dawn_mesh/core/session/room_session.dart';
import 'package:dawn_mesh/ui/pages/room_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Finder textEither(String zh, String en) => find.byWidgetPredicate(
    (widget) => widget is Text && (widget.data == zh || widget.data == en),
  );

  for (final mode in RoomMode.values) {
    testWidgets('${mode.name} host confirms before dissolving', (tester) async {
      final session = RoomSession(
        audioIo: MockAudioIo(),
        selfNickname: '房主#001',
        mode: mode,
      );
      await session.createRoom(startAudio: false);
      var leaveCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomContent(
              session: session,
              isNight: false,
              stage: const AlwaysStoppedAnimation(1),
              onLeave: () => leaveCount++,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.call_end));
      await tester.pump();
      expect(textEither('解散房间？', 'Dissolve this room?'), findsOneWidget);
      expect(leaveCount, 0);
      await tester.tap(textEither('取消', 'Cancel'));
      await tester.pump();
      expect(leaveCount, 0);

      await tester.tap(find.byIcon(Icons.call_end));
      await tester.pump();
      await tester.tap(textEither('解散房间', 'Dissolve room'));
      await tester.pump();
      expect(leaveCount, 1);

      await session.dispose();
    });
  }

  testWidgets('member confirms before leaving a local room', (tester) async {
    final session = RoomSession(audioIo: MockAudioIo(), selfNickname: '成员#002');
    var leaveCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomContent(
            session: session,
            isNight: false,
            stage: const AlwaysStoppedAnimation(1),
            onLeave: () => leaveCount++,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.call_end));
    await tester.pump();
    expect(textEither('退出房间？', 'Leave this room?'), findsOneWidget);
    expect(leaveCount, 0);
    await tester.tap(textEither('退出房间', 'Leave room'));
    await tester.pump();
    expect(leaveCount, 1);

    await session.dispose();
  });
}
