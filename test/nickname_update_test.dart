import 'dart:typed_data';

import 'package:dawn_mesh/core/audio/audio_io.dart';
import 'package:dawn_mesh/core/protocol/frame.dart';
import 'package:dawn_mesh/core/protocol/frame_type.dart';
import 'package:dawn_mesh/core/protocol/payloads/join_request.dart';
import 'package:dawn_mesh/core/protocol/payloads/roster.dart';
import 'package:dawn_mesh/core/session/room_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'active local member nickname updates without leaving the room',
    () async {
      final sent = <Frame>[];
      final guest = RoomSession(
        audioIo: MockAudioIo(),
        selfNickname: '旧昵称#1234',
      )..onSendFrame = sent.add;
      guest.handleIncomingFrame(
        Frame(
          type: FrameType.roster,
          senderId: 1,
          seq: 1,
          payload: RosterPayload(
            hostId: 1,
            members: [
              RosterMember(memberId: 1, flags: 1, nickname: '房主#0001'),
              RosterMember(memberId: 2, flags: 0, nickname: '旧昵称#1234'),
            ],
          ).encode(),
        ),
      );

      await guest.updateNickname('新昵称#1234');

      expect(guest.selfNickname, '新昵称#1234');
      expect(
        guest.members.singleWhere((member) => member.memberId == 2).nickname,
        '新昵称#1234',
      );
      expect(sent.last.type, FrameType.nicknameUpdate);

      final hostSent = <Frame>[];
      final host = RoomSession(audioIo: MockAudioIo(), selfNickname: '房主#0001')
        ..onSendFrame = hostSent.add;
      await host.createRoom(startAudio: false);
      await host.handleIncomingFrame(
        Frame(
          type: FrameType.joinReq,
          senderId: 0,
          seq: 2,
          payload: JoinRequestPayload(
            nickname: '旧昵称#1234',
            sessionToken: Uint8List.fromList(List<int>.filled(16, 7)),
          ).encode(),
        ),
      );
      hostSent.clear();
      await host.handleIncomingFrame(sent.last);

      expect(
        host.members.singleWhere((member) => member.memberId == 2).nickname,
        '新昵称#1234',
      );
      expect(hostSent.any((frame) => frame.type == FrameType.roster), isTrue);

      await guest.dispose();
      await host.dispose();
    },
  );
}
