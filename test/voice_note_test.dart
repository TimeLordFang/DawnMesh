import 'dart:typed_data';

import 'package:dawn_mesh/core/audio/audio_io.dart';
import 'package:dawn_mesh/core/transport/ble_l2cap_transport.dart';
import 'package:dawn_mesh/core/protocol/frame.dart';
import 'package:dawn_mesh/core/protocol/frame_type.dart';
import 'package:dawn_mesh/core/session/room_session.dart';
import 'package:dawn_mesh/core/session/voice_note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'voice container rejects malformed lengths and caps retained duration',
    () {
      final capture = VoiceNoteCapture(1, 100, '123');
      for (var i = 0; i < 750; i++) {
        expect(capture.add(Uint8List.fromList([1, 2, 3])), true);
      }
      expect(capture.add(Uint8List.fromList([1])), false);
      final note = VoiceNote.decode(capture.finish().encode())!;
      expect(note.duration, const Duration(seconds: 15));
      expect(note.packets, hasLength(750));
      expect(VoiceNote.decode(Uint8List.fromList([1, 0, 1, 255, 255])), isNull);
      expect(
        VoiceNote.decode(Uint8List.fromList([...capture.finish().encode(), 0])),
        isNull,
      );
    },
  );

  test('PTT retention is opt-in; live and repaired chunks create one note; recall cannot resurrect it', () async {
    final audio = MockAudioIo();
    final host = RoomSession(
      audioIo: audio,
      selfNickname: 'Host#123',
      mode: RoomMode.bluetoothPtt,
    );
    final guest = RoomSession(
      audioIo: MockAudioIo(),
      selfNickname: 'Guest#234',
      mode: RoomMode.bluetoothPtt,
    );
    final wires = <(RoomSession, Frame)>[];
    final sent = <Frame>[];
    host.onSendFrame = (frame) {
      wires.add((guest, frame));
      sent.add(frame);
    };
    guest.onSendFrame = (frame) {
      wires.add((host, frame));
    };
    addTearDown(() async {
      host.onSendFrame = null;
      guest.onSendFrame = null;
      await host.dispose();
      await guest.dispose();
    });
    Future<void> pump() async {
      var budget = 10000;
      for (var idle = 0; idle < 3;) {
        if (wires.isEmpty) {
          idle++;
          await Future<void>.delayed(Duration.zero);
          continue;
        }
        idle = 0;
        expect(--budget, greaterThan(0));
        final (target, frame) = wires.removeAt(0);
        await target.handleIncomingFrame(frame);
      }
    }

    await host.createRoom();
    await guest.joinRoom(startAudio: false);
    await pump();
    expect(guest.state, RoomState.inRoom);
    host.setPtt(true);
    audio.emitEncodedFrame(Uint8List.fromList([1, 2, 3]));
    host.setPtt(false);
    await pump();
    expect(host.chatMessages, isEmpty);
    expect(guest.chatMessages, isEmpty);
    // A text-only recipient must not acquire a permanent note placeholder or
    // a native audio stream from other members' retained/live PTT traffic.
    final textLink = BleL2capTransport()..textOnly = true;
    guest.transport = textLink;
    final guestAudio = guest.audioIo as MockAudioIo;
    guestAudio.submittedFrames.clear();
    host.setRetainVoiceNotes(true);
    host.setPtt(true);
    audio.emitEncodedFrame(Uint8List.fromList([7, 8]));
    await pump();
    host.setPtt(false);
    await pump();
    expect(guest.chatMessages, isEmpty);
    expect(guestAudio.submittedFrames, isEmpty);
    await host.recallMessage(host.chatMessages.single.messageId);
    await pump();
    guest.transport = null;
    await textLink.dispose();
    sent.clear();
    host.setPtt(true);
    for (var i = 0; i < 20; i++) {
      audio.emitEncodedFrame(Uint8List.fromList(List.filled(60, i)));
    }
    await pump();
    expect(guest.chatMessages.single.voicePending, true);
    final stableId = guest.chatMessages.single.messageId;
    host.setPtt(false);
    await pump();
    expect(guest.chatMessages, hasLength(1));
    expect(guest.chatMessages.single.messageId, stableId);
    expect(guest.chatMessages.single.voiceNote!.packets, hasLength(20));
    final chunks = sent.where((f) => f.type == FrameType.voiceNote).toList();
    expect(chunks.length, greaterThan(1));
    for (final chunk in chunks.reversed) {
      await guest.handleIncomingFrame(chunk);
    }
    expect(guest.chatMessages, hasLength(1));
    await host.recallMessage(stableId);
    await pump();
    for (final chunk in chunks) {
      await guest.handleIncomingFrame(chunk);
    }
    expect(guest.chatMessages, isEmpty);
    host.setPtt(true);
    audio.emitEncodedFrame(Uint8List.fromList([3, 4]));
    await pump();
    host.cancelVoiceNote();
    host.setPtt(false);
    await pump();
    expect(host.chatMessages, isEmpty);
    expect(guest.chatMessages, isEmpty);
  });
}
