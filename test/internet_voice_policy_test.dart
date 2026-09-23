import 'package:dawn_mesh/core/internet/internet_models.dart';
import 'package:dawn_mesh/core/internet/internet_room_api.dart';
import 'package:dawn_mesh/core/internet/internet_room_session.dart';
import 'package:dawn_mesh/core/session/room_session.dart' show VoiceMode;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const profile = ServerProfile(
    id: 'voice-policy-test',
    name: 'Test server',
    baseUrl: 'https://talk.example.test',
  );

  InternetRoomSession makeSession(List<bool> microphoneStates) {
    final session = InternetRoomSession.forTesting(
      api: InternetRoomApi(profile),
      profile: profile,
      nickname: 'Member',
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
}
