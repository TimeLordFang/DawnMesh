import 'package:dawn_mesh/core/internet/internet_models.dart';
import 'package:dawn_mesh/core/internet/internet_room_api.dart';
import 'package:dawn_mesh/core/internet/internet_room_session.dart';
import 'package:dawn_mesh/ui/pages/internet_room_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'a dissolved room notifies the member and returns after ten seconds',
    (tester) async {
      const profile = ServerProfile(
        id: 'server-test',
        name: '测试服务器',
        baseUrl: 'https://talk.example.test',
      );
      final session = InternetRoomSession.forTesting(
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
      );

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
}
