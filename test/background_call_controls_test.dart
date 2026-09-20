import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dawn_mesh/core/audio/audio_io.dart';
import 'package:dawn_mesh/core/internet/internet_models.dart';
import 'package:dawn_mesh/core/internet/internet_room_api.dart';
import 'package:dawn_mesh/core/internet/internet_room_session.dart';
import 'package:dawn_mesh/core/platform/platform_audio_channel.dart';
import 'package:dawn_mesh/core/session/room_session.dart';

class DelayedAudio extends MockAudioIo {
  final waiting = Completer<void>();
  bool first = true;
  int captureStarts = 0;
  @override
  Future<void> stopCapture() async {
    if (first) {
      first = false;
      await waiting.future;
    }
    await super.stopCapture();
  }

  @override
  Future<void> startCapture(
    OpusFrameCallback callback, {
    int bitrateBps = 24000,
  }) async {
    captureStarts++;
    await super.startCapture(callback, bitrateBps: bitrateBps);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('leaving during audio startup does not reopen the microphone', () async {
    final audio = DelayedAudio();
    final room = RoomSession(audioIo: audio, selfNickname: 'Host');
    await room.createRoom(startAudio: false);
    final opening = room.startAudio();
    await room.leave();
    audio.waiting.complete();
    await opening;
    expect(audio.captureStarts, 0);
    expect(audio.isRecording, isFalse);
    await room.dispose();
  });

  test(
    'lock-screen controls switch mode, gate PTT and mute, then detach on leave',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const controlsName = 'dev.dawnmesh.intercom/call_controls';
      const codec = StandardMethodCodec();
      final updates = <Map<Object?, Object?>>[];
      for (final name in [
        'dev.dawnmesh.intercom/audio',
        'dev.dawnmesh.intercom/audio_events',
        controlsName,
      ]) {
        messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
          if (name == controlsName) {
            updates.add(Map<Object?, Object?>.from(call.arguments as Map));
          }
          return true;
        });
        addTearDown(
          () => messenger.setMockMethodCallHandler(MethodChannel(name), null),
        );
      }
      final room = RoomSession(
        audioIo: PlatformAudioChannel(),
        selfNickname: 'Host',
        mode: RoomMode.bluetoothPtt,
      );
      await room.createRoom();
      Future<void> native(String method, bool value) async {
        final done = Completer<void>();
        await messenger.handlePlatformMessage(
          controlsName,
          codec.encodeMethodCall(MethodCall(method, value)),
          (_) => done.complete(),
        );
        await done.future;
      }

      await native('ptt', true);
      expect(room.isPttPressed, isTrue);
      await native('automatic', true);
      expect(room.voiceMode, VoiceMode.automatic);
      expect(room.isPttPressed, isFalse);
      await native('mute', true);
      expect(room.isMuted, isTrue);
      await native('automatic', false);
      await native('ptt', true);
      expect(room.isPttPressed, isFalse);
      await native('mute', false);
      await native('ptt', true);
      expect(room.isPttPressed, isTrue);
      await native('ptt', false);
      expect(room.isPttPressed, isFalse);
      await room.dispose();
      expect(updates.last['active'], isFalse);
      expect(room.audioIo.isRecording, isFalse);
    },
  );

  test('public-room lock-screen control switches voice mode', () async {
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
        memberCount: 1,
        maxParticipants: 25,
        hostNickname: '群主',
      ),
    );

    await session.handleBackgroundCommandForTesting('automatic', true);
    expect(session.voiceMode, VoiceMode.automatic);
    await session.handleBackgroundCommandForTesting('automatic', false);
    expect(session.voiceMode, VoiceMode.pushToTalk);
    await session.updateNickname('新昵称');
    expect(session.nickname, '新昵称');

    await session.disposeSession();
  });
}
