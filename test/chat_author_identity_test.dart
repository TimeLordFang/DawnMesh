import 'package:dawn_mesh/core/audio/audio_io.dart';
import 'package:dawn_mesh/core/protocol/frame.dart';
import 'package:dawn_mesh/core/protocol/frame_type.dart';
import 'package:dawn_mesh/core/protocol/payloads/chat_delete.dart';
import 'package:dawn_mesh/core/security/member_identity.dart';
import 'package:dawn_mesh/core/security/room_invite.dart';
import 'package:dawn_mesh/core/session/room_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'same short code cannot recall another key’s current or delayed message',
    () async {
      final host = RoomSession(audioIo: MockAudioIo(), selfNickname: 'A#123');
      final guest = RoomSession(audioIo: MockAudioIo(), selfNickname: 'B#123');
      final observer = RoomSession(
        audioIo: MockAudioIo(),
        selfNickname: 'C#456',
      );
      final peers = [host, guest, observer];
      final wires = <(RoomSession, Frame)>[];
      for (final peer in peers) {
        peer.onSendFrame = (frame) {
          for (final other in peers) {
            if (other != peer) wires.add((other, frame));
          }
        };
      }
      addTearDown(() async {
        for (final peer in peers) {
          peer.onSendFrame = null;
        }
        for (final peer in peers) {
          await peer.dispose();
        }
      });
      Future<void> pump() async {
        var budget = 1000;
        for (var idle = 0; idle < 5;) {
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

      final invite = RoomInvite.parse('1234');
      await host.protectWithInvite(
        invite,
        identity: await MemberIdentity.create(),
      );
      await guest.protectWithInvite(
        invite,
        identity: await MemberIdentity.create(),
      );
      await host.createRoom(startAudio: false);
      await guest.joinRoom(startAudio: false);
      await pump();
      await observer.protectWithInvite(
        invite,
        identity: await MemberIdentity.create(),
      );
      await observer.joinRoom(startAudio: false);
      await pump();
      expect(observer.state, RoomState.inRoom);
      expect(guest.state, RoomState.inRoom);
      await host.sendChat('same code, different key');
      await pump();
      final first = host.chatMessages.last.messageId;
      await expectLater(guest.recallMessage(first), throwsStateError);
      Future<void> forgedRecall(String id) async {
        await guest.sendFrame(
          Frame(
            type: FrameType.chatDelete,
            senderId: guest.selfMemberId,
            seq: 400,
            payload: ChatDeletePayload(
              senderCode: '123',
              messageId: id,
            ).encode(),
          ),
        );
        await pump();
      }

      await forgedRecall(first);
      expect(host.chatMessages.any((m) => m.messageId == first), true);
      // Forge a recall before the authenticated original reaches this receiver.
      await host.sendChat('arrives after forged recall');
      final delayed = List<(RoomSession, Frame)>.from(wires);
      wires.clear();
      final second = host.chatMessages.last.messageId;
      final forged = Frame(
        type: FrameType.chatDelete,
        senderId: guest.selfMemberId,
        seq: 401,
        payload: ChatDeletePayload(
          senderCode: '123',
          messageId: second,
        ).encode(),
      );
      final sealed = await guest.secureCodec!.seal(forged);
      await observer.handleIncomingFrame(sealed);
      wires.addAll(delayed);
      await pump();
      expect(observer.chatMessages.any((m) => m.messageId == second), true);
      await host.recallMessage(second);
      await pump();
      expect(observer.chatMessages.any((m) => m.messageId == second), false);
      expect(first.length, lessThanOrEqualTo(64));
    },
  );
}
