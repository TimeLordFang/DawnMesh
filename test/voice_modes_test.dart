import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/audio/audio_io.dart';
import 'package:sunset_ripple/core/audio/voice_activity_gate.dart';
import 'package:sunset_ripple/core/protocol/frame.dart';
import 'package:sunset_ripple/core/protocol/frame_type.dart';
import 'package:sunset_ripple/core/session/room_session.dart';
import 'package:sunset_ripple/ui/pages/room_page.dart';
import 'package:sunset_ripple/ui/widgets/voice_mode_switch.dart';

void main() {
  test('voice gate drops silence, retains onset, hangs over and closes', () {
    final gate = VoiceActivityGate();
    for (var i = 0; i < 10; i++) {
      expect(gate.process(Uint8List.fromList([i]), 0, i * 20), isEmpty);
    }
    final onset = gate.process(Uint8List.fromList([10]), 0.1, 200);
    expect(onset.map((p) => p.single), [5, 6, 7, 8, 9, 10]);
    expect(gate.process(Uint8List.fromList([11]), 0, 220), hasLength(1));
    expect(gate.process(Uint8List.fromList([12]), 0, 601), isEmpty);
    gate.reset();
    expect(gate.process(Uint8List.fromList([13]), 0, 602), isEmpty);
    expect(gate.isOpen, isFalse);
  });

  test(
    'Bluetooth switches locally without restarting capture, mute/leave stop sending',
    () async {
      final audio = MockAudioIo();
      final room = RoomSession(
        audioIo: audio,
        selfNickname: 'Host',
        mode: RoomMode.bluetoothPtt,
      );
      addTearDown(room.dispose);
      final sent = <Frame>[];
      room.onSendFrame = sent.add;
      await room.createRoom();
      expect(audio.bitrate, 16000);
      audio.emitEncodedFrame(Uint8List.fromList([1]), level: .2);
      expect(sent.where((f) => f.type == FrameType.audio), isEmpty);
      room.setPtt(true);
      audio.emitEncodedFrame(Uint8List.fromList([2]), level: .2);
      room.setPtt(false);
      audio.emitEncodedFrame(Uint8List.fromList([3]), level: .2);
      expect(
        sent
            .where((f) => f.type == FrameType.audio)
            .map((f) => f.payload.single),
        [2],
      );
      room.setVoiceMode(VoiceMode.automatic);
      audio.emitEncodedFrame(Uint8List.fromList([4]), level: 0);
      audio.emitEncodedFrame(Uint8List.fromList([5]), level: .2);
      expect(sent.where((f) => f.type == FrameType.audio).last.payload, [5]);
      expect(room.isPttPressed, isFalse);
      room.toggleMute();
      final count = sent.where((f) => f.type == FrameType.audio).length;
      audio.emitEncodedFrame(Uint8List.fromList([6]), level: .2);
      expect(sent.where((f) => f.type == FrameType.audio).length, count);
      room.toggleMute();
      room.setVoiceMode(VoiceMode.pushToTalk);
      audio.emitEncodedFrame(Uint8List.fromList([7]), level: .2);
      expect(sent.where((f) => f.type == FrameType.audio).length, count);
      expect(audio.isRecording, isTrue);
      await room.leave();
      audio.emitEncodedFrame(Uint8List.fromList([8]), level: .2);
      expect(sent.where((f) => f.type == FrameType.audio).length, count);
      expect(audio.isRecording, isFalse);
    },
  );

  test('Wi-Fi room can switch between automatic and push-to-talk', () async {
    final audio = MockAudioIo();
    final room = RoomSession(
      audioIo: audio,
      selfNickname: 'Host',
      mode: RoomMode.wifiFullDuplex,
    );
    addTearDown(room.dispose);
    final sent = <Frame>[];
    room.onSendFrame = sent.add;
    await room.createRoom();
    expect(room.voiceMode, VoiceMode.automatic);
    room.setVoiceMode(VoiceMode.pushToTalk);
    audio.emitEncodedFrame(Uint8List.fromList([1]), level: .2);
    expect(sent.where((frame) => frame.type == FrameType.audio), isEmpty);
    room.setPtt(true);
    audio.emitEncodedFrame(Uint8List.fromList([2]), level: .2);
    expect(
      sent.where((frame) => frame.type == FrameType.audio).single.payload,
      [2],
    );
    room.setVoiceMode(VoiceMode.automatic);
    expect(room.isPttPressed, isFalse);
    audio.emitEncodedFrame(Uint8List.fromList([3]), level: .2);
    expect(sent.where((frame) => frame.type == FrameType.audio).last.payload, [
      3,
    ]);
  });

  testWidgets(
    'compact Bluetooth room switches both voice modes without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final room = RoomSession(
        audioIo: MockAudioIo(),
        selfNickname: 'Host',
        mode: RoomMode.bluetoothPtt,
      );
      await room.createRoom(startAudio: false);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomContent(
              session: room,
              isNight: false,
              stage: const AlwaysStoppedAnimation(1),
              onLeave: () {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('自动通话'));
      await tester.pump();
      expect(room.voiceMode, VoiceMode.automatic);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('按住对讲'));
      await tester.pump();
      expect(room.voiceMode, VoiceMode.pushToTalk);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      var disposed = false;
      room.dispose().then((_) => disposed = true);
      for (var i = 0; i < 20 && !disposed; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(disposed, isTrue);
    },
  );

  testWidgets('voice mode switch adapts to large text and keeps both targets', (
    tester,
  ) async {
    var selected = VoiceMode.pushToTalk;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Center(
              child: SizedBox(
                width: 300,
                child: StatefulBuilder(
                  builder:
                      (context, setState) => VoiceModeSwitch(
                        value: selected,
                        isNight: true,
                        onChanged: (mode) => setState(() => selected = mode),
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('按住对讲'), findsOneWidget);
    expect(find.text('自动通话'), findsOneWidget);
    expect(find.text('按住发送'), findsNothing);
    expect(find.text('声音触发'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('自动通话'));
    await tester.pumpAndSettle();
    expect(selected, VoiceMode.automatic);
    expect(tester.takeException(), isNull);
  });
}
