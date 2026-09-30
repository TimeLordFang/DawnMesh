import 'package:dawn_mesh/core/internet/internet_models.dart';
import 'package:dawn_mesh/core/internet/internet_room_api.dart';
import 'package:dawn_mesh/core/internet/internet_room_session.dart';
import 'package:dawn_mesh/ui/pages/internet_room_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const profile = ServerProfile(
    id: 'test',
    name: 'test',
    baseUrl: 'https://example.test',
  );
  InternetRoomSession session({bool host = false}) =>
      InternetRoomSession.forTesting(
        api: InternetRoomApi(profile),
        profile: profile,
        nickname: 'self',
        roomId: 'room',
        memberId: 'me',
        isHost: host,
        summary: const InternetRoomSummary(
          id: 'room',
          name: 'room',
          memberCount: 2,
          maxParticipants: 25,
          hostNickname: 'self',
          presenceAnnouncementsSupported: true,
        ),
      );
  Map<String, dynamic> snapshot(bool online, {bool includePeer = true}) => {
    'type': 'snapshot',
    'hostMemberId': 'me',
    'members': [
      {
        'id': 'me',
        'nickname': 'self',
        'connected': true,
        'isHost': true,
        'joinOrder': 0,
      },
      if (includePeer)
        {'id': 'peer', 'nickname': '离线成员', 'connected': online, 'joinOrder': 1},
    ],
  };
  test('roster retains offline members and stable order, removes explicit departures', () async {
    final room = session();
    await room.receiveManagementForTesting(snapshot(true));
    await room.receiveManagementForTesting(snapshot(false));
    expect(room.members.map((m) => m.id), ['me', 'peer']);
    expect(room.members.last.isOnline, isFalse);
    await room.receiveManagementForTesting(snapshot(true));
    expect(room.members.last.isOnline, isTrue);
    await room.receiveManagementForTesting(snapshot(true, includePeer: false));
    expect(room.members.map((m) => m.id), ['me']);
    await room.disposeSession();
  });
  test(
    'media membership wins over control outages and restores promptly',
    () async {
      final room = session();
      addTearDown(room.disposeSession);
      room.receiveMediaRosterForTesting({'me', 'peer'});
      await room.receiveManagementForTesting(snapshot(false));
      expect(room.members.last.isOnline, isTrue);
      room.receiveMediaRosterForTesting({'me'});
      expect(room.members.last.isOnline, isFalse);
      await room.receiveManagementForTesting(snapshot(true));
      expect(room.members.last.isOnline, isFalse);
      room.receiveMediaRosterForTesting({'me', 'peer'});
      expect(room.members.last.isOnline, isTrue);
      room.receiveMediaRosterForTesting({}, connected: false);
      await room.receiveManagementForTesting(snapshot(false));
      expect(room.members.last.isOnline, isTrue);
      room.receiveMediaRosterForTesting({'me', 'peer'});
      expect(room.members.last.isOnline, isTrue);
    },
  );
  testWidgets(
    'offline badge stays visible and host controls are inside room settings',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final room = session(host: true);
      await room.receiveManagementForTesting(snapshot(false));
      addTearDown(room.disposeSession);
      await tester.pumpWidget(
        MaterialApp(home: InternetRoomPage(session: room, isNight: false)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('member-offline-badge')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('presence-announcements-control')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('room-settings-button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('presence-announcements-control')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('noise-reduction-control')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
