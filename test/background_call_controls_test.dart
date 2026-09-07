import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/audio/audio_io.dart';
import 'package:sunset_ripple/core/platform/platform_audio_channel.dart';
import 'package:sunset_ripple/core/session/room_session.dart';

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
        'host.msknet.sunsetripple/audio',
        'host.msknet.sunsetripple/audio_events',
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
}
