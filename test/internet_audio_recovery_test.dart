import 'dart:async';

import 'package:dawn_mesh/core/internet/intercom_audio_track.dart';
import 'package:dawn_mesh/core/internet/internet_models.dart';
import 'package:dawn_mesh/core/internet/internet_room_api.dart';
import 'package:dawn_mesh/core/internet/internet_room_session.dart';
import 'package:dawn_mesh/core/session/room_session.dart' show VoiceMode;
import 'package:flutter_test/flutter_test.dart';

class _Capture extends Fake implements IntercomAudioTrack {
  final operations = <String>[];
  @override
  void blockTransmission() {}
  @override
  Future<bool> mute({bool stopOnMute = true}) async {
    operations.add('mute');
    return true;
  }

  @override
  Future<bool> unmute({bool stopOnMute = true}) async {
    operations.add('unmute');
    return true;
  }

  @override
  Future<bool> stop() async {
    operations.add('stop');
    return true;
  }

  @override
  Future<bool> release() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const profile = ServerProfile(
    id: 'test',
    name: 'test',
    baseUrl: 'https://example.test',
  );
  InternetRoomSession make(List<bool> states, Future<void> Function() recover) {
    final session = InternetRoomSession.forTesting(
      api: InternetRoomApi(profile),
      profile: profile,
      nickname: 'test',
      roomId: 'room',
      memberId: 'me',
      summary: const InternetRoomSummary(
        id: 'room',
        name: 'room',
        memberCount: 1,
        maxParticipants: 25,
        hostNickname: 'test',
      ),
      microphoneForTesting: (enabled) async => states.add(enabled),
      audioRecoveryForTesting: recover,
    );
    addTearDown(session.disposeSession);
    return session;
  }

  test(
    'headset recovery while muted waits until speaking is permitted',
    () async {
      var recoveries = 0;
      final states = <bool>[];
      final session = make(states, () async {
        recoveries++;
      });
      await session.recoverAudioRoute();
      expect(recoveries, 0);
      expect(states.last, isFalse);
      await session.setPtt(true);
      expect(recoveries, 1);
      expect(states.last, isTrue);
      await session.setPtt(false);
      expect(states.last, isFalse);
      await session.receiveVoicePolicyForTesting(false);
      await session.recoverAudioRoute();
      expect(recoveries, 1);
      expect(states.last, isFalse);
    },
  );
  test(
    'focus loss releases PTT and regain respects voice mode and mute',
    () async {
      final states = <bool>[];
      final session = make(states, () async {});
      await session.setPtt(true);
      await session.handleBackgroundCommandForTesting('audioFocus', false);
      expect(states.last, isFalse);
      await session.handleBackgroundCommandForTesting('audioFocus', true);
      expect(states.last, isFalse);
      await session.setVoiceMode(VoiceMode.automatic);
      expect(states.last, isTrue);
      await session.handleBackgroundCommandForTesting('audioFocus', false);
      expect(states.last, isFalse);
      await session.toggleMute();
      await session.handleBackgroundCommandForTesting('audioFocus', true);
      expect(states.last, isFalse);
    },
  );

  test('foreground failure prevents reopening capture', () async {
    final states = <bool>[];
    final session = make(states, () async {});
    await session.setVoiceMode(VoiceMode.automatic);
    await session.handleBackgroundCommandForTesting('serviceFailed', 'denied');
    expect(states.last, isFalse);
    await session.toggleMute();
    expect(states.last, isFalse);
    await session.handleBackgroundCommandForTesting('audioFocus', true);
    await session.setPtt(true);
    expect(states.last, isFalse);
  });
  test('focus interruption stops capture without discarding its publication identity', () async {
    final capture = _Capture();
    final session = InternetRoomSession.forTesting(
      api: InternetRoomApi(profile),
      profile: profile,
      nickname: 'test',
      roomId: 'room',
      memberId: 'me',
      summary: const InternetRoomSummary(
        id: 'room',
        name: 'room',
        memberCount: 1,
        maxParticipants: 25,
        hostNickname: 'test',
      ),
      ownedMicrophoneForTesting: capture,
      audioRecoveryForTesting: () async => capture.operations.add('restart'),
    );
    addTearDown(session.disposeSession);
    await session.setVoiceMode(VoiceMode.automatic);
    capture.operations.clear();
    await session.handleBackgroundCommandForTesting('audioFocus', false);
    expect(capture.operations, ['mute', 'stop']);
    await session.handleBackgroundCommandForTesting('audioFocus', true);
    expect(capture.operations, ['mute', 'stop', 'restart', 'unmute']);
    capture.operations.clear();
    await session.handleBackgroundCommandForTesting('serviceFailed', 'denied');
    expect(capture.operations, ['mute', 'stop']);
    await session.handleBackgroundCommandForTesting('audioFocus', true);
    expect(capture.operations, ['mute', 'stop']);
  });
  test(
    'PTT release during asynchronous capture recovery cannot reopen mic',
    () async {
      final states = <bool>[];
      final started = Completer<void>();
      final finish = Completer<void>();
      final session = make(states, () async {
        started.complete();
        await finish.future;
      });
      await session.setPtt(true);
      states.clear();
      final recovery = session.recoverAudioRoute();
      await started.future;
      final released = session.setPtt(false);
      finish.complete();
      await Future.wait([recovery, released]);
      expect(states, everyElement(isFalse));
    },
  );
  test(
    'automatic talk restores after route change without altering mute choice',
    () async {
      var recoveries = 0;
      final states = <bool>[];
      final session = make(states, () async {
        recoveries++;
      });
      await session.setVoiceMode(VoiceMode.automatic);
      await session.recoverAudioRoute();
      expect(recoveries, 1);
      expect(states.last, isTrue);
      await session.toggleMute();
      await session.recoverAudioRoute();
      expect(recoveries, 1);
      expect(states.last, isFalse);
      await session.toggleMute();
      expect(recoveries, 2);
      expect(states.last, isTrue);
    },
  );
}
