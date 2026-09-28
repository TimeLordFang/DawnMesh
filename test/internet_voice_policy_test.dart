import 'package:dawn_mesh/core/internet/internet_models.dart';
import 'package:dawn_mesh/core/internet/internet_room_api.dart';
import 'package:dawn_mesh/core/internet/internet_room_session.dart';
import 'package:dawn_mesh/core/session/room_session.dart' show VoiceMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:dawn_mesh/ui/pages/internet_room_page.dart';

void main() {
  const profile = ServerProfile(
    id: 'voice-policy-test',
    name: 'Test server',
    baseUrl: 'https://talk.example.test',
  );

  InternetRoomSession makeSession(
    List<bool> microphoneStates, {
    bool host = false,
    VoidCallback? mediaReady,
  }) {
    final session = InternetRoomSession.forTesting(
      api: InternetRoomApi(profile),
      profile: profile,
      nickname: 'Member',
      isHost: host,
      mediaReadyForTesting: mediaReady,
      roomId: 'room-test',
      memberId: 'member-test',
      summary: const InternetRoomSummary(
        id: 'room-test',
        name: 'Test room',
        memberCount: 2,
        maxParticipants: 25,
        hostNickname: 'Host',
      ),
      microphoneForTesting: (enabled) async => microphoneStates.add(enabled),
    );
    addTearDown(session.disposeSession);
    return session;
  }

  test(
    'automatic talk resumes when the host restores speaking permission',
    () async {
      final microphoneStates = <bool>[];
      final session = makeSession(microphoneStates);
      await session.setVoiceMode(VoiceMode.automatic);
      expect(microphoneStates.last, isTrue);

      await session.receiveVoicePolicyForTesting(false);
      expect(session.canSpeak, isFalse);
      expect(microphoneStates.last, isFalse);

      await session.receiveVoicePolicyForTesting(true);
      expect(session.canSpeak, isTrue);
      expect(session.voiceMode, VoiceMode.automatic);
      expect(microphoneStates.last, isTrue);
    },
  );

  test(
    'media permission arriving after policy restores automatic talk',
    () async {
      final microphoneStates = <bool>[];
      final session = makeSession(microphoneStates);
      await session.setVoiceMode(VoiceMode.automatic);

      await session.receiveMediaPermissionForTesting(false);
      await session.receiveVoicePolicyForTesting(false);
      await session.receiveVoicePolicyForTesting(true);
      expect(session.canSpeak, isFalse);
      expect(microphoneStates.last, isFalse);

      await session.receiveMediaPermissionForTesting(true);
      expect(session.canSpeak, isTrue);
      expect(microphoneStates.last, isTrue);
    },
  );

  test(
    'push-to-talk stays idle after permission returns until pressed again',
    () async {
      final microphoneStates = <bool>[];
      final session = makeSession(microphoneStates);
      await session.setPtt(true);
      expect(microphoneStates.last, isTrue);

      await session.receiveVoicePolicyForTesting(false);
      expect(session.isPttPressed, isFalse);
      expect(microphoneStates.last, isFalse);
      await session.receiveVoicePolicyForTesting(true);
      expect(microphoneStates.last, isFalse);

      await session.setPtt(true);
      expect(microphoneStates.last, isTrue);
    },
  );
  testWidgets(
    'host permission sync retries then stops after SDK confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var requests = 0;
      final microphone = <bool>[];
      final session = makeSession(
        microphone,
        host: true,
        mediaReady: () => requests++,
      );
      await session.setVoiceMode(VoiceMode.automatic);
      await session.receiveMediaPermissionForTesting(false);
      expect(session.isMutedByHost, isFalse);
      expect(session.awaitingMediaPermission, isTrue);
      expect(session.canSpeak, isFalse);
      expect(microphone.last, isFalse);
      expect(requests, 1);
      await tester.pump(const Duration(seconds: 10));
      expect(requests, 2);
      await tester.pumpWidget(
        MaterialApp(home: InternetRoomPage(session: session, isNight: false)),
      );
      await tester.pump();
      expect(find.text('房主已关闭你的麦克风'), findsNothing);
      expect(find.textContaining('正在恢复发言权限…'), findsOneWidget);
      await session.receiveMediaPermissionForTesting(true);
      expect(session.canSpeak, isTrue);
      expect(microphone.last, isTrue);
      await tester.pump(const Duration(seconds: 30));
      expect(requests, 2);
      await tester.pumpWidget(const SizedBox());
      await session.disposeSession();
    },
  );
  test(
    'muted member promoted to host clears policy block but still waits for SDK',
    () async {
      final microphone = <bool>[];
      final session = makeSession(microphone);
      await session.setVoiceMode(VoiceMode.automatic);
      await session.receiveVoicePolicyForTesting(false);
      await session.receiveMediaPermissionForTesting(false);
      await session.receiveManagementForTesting({
        'type': 'role_changed',
        'hostMemberId': 'member-test',
        'members': [
          {
            'id': 'member-test',
            'nickname': 'Member',
            'isHost': true,
            'canSpeak': true,
          },
        ],
      });
      expect(session.isHost, isTrue);
      expect(session.isMutedByHost, isFalse);
      expect(session.canSpeak, isFalse);
      await session.receiveMediaPermissionForTesting(true);
      expect(session.canSpeak, isTrue);
      expect(microphone.last, isTrue);
    },
  );
  test('recovery roster restores missed policy update without enabling a muted member', () async {
    final microphone = <bool>[];
    final session = makeSession(microphone);
    await session.setVoiceMode(VoiceMode.automatic);
    await session.receiveVoicePolicyForTesting(false);
    await session.receiveManagementForTesting({
      'type': 'snapshot',
      'hostMemberId': 'host',
      'members': [
        {'id': 'member-test', 'nickname': 'Member', 'canSpeak': true},
      ],
    });
    expect(session.canSpeak, isTrue);
    expect(microphone.last, isTrue);
    await session.receiveManagementForTesting({
      'type': 'snapshot',
      'hostMemberId': 'host',
      'members': [
        {'id': 'member-test', 'nickname': 'Member', 'canSpeak': false},
      ],
    });
    expect(session.isMutedByHost, isTrue);
    expect(microphone.last, isFalse);
  });
}
