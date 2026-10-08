import 'dart:convert';
import 'dart:typed_data';

import 'package:dawn_mesh/core/protocol/control_fragments.dart';
import 'package:dawn_mesh/core/protocol/frame.dart';
import 'package:dawn_mesh/core/protocol/frame_type.dart';
import 'package:dawn_mesh/core/protocol/payloads/roster.dart';
import 'package:dawn_mesh/core/security/session_crypto.dart';
import 'package:dawn_mesh/core/security/session_handshake.dart';
import 'package:dawn_mesh/core/session/host_transfer.dart';
import 'package:dawn_mesh/core/fusion/fusion_peer_topology.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    '16 long Unicode names survive encrypted out-of-order fragments',
    () async {
      final payload = RosterPayload(
        hostId: 1,
        members: [
          for (var i = 1; i <= 16; i++)
            RosterMember(
              memberId: i,
              flags: i == 1 ? 1 : 0,
              nickname: '$i${'声' * 21}🎧',
            ),
        ],
      ).encode();
      expect(payload.length, greaterThan(Frame.maxPayloadSize));
      var seq = 0;
      final parts = ControlFragments.split(
        type: FrameType.roster,
        senderId: 1,
        messageId: 42,
        payload: payload,
        maxPayload: SecureFrameCodec.maxPlaintextPayload,
        nextSeq: () => seq++,
      ).toList();
      final sender = SecureFrameCodec(
        await SessionCipher.fromKey(Uint8List(32)),
      );
      final receiver = SecureFrameCodec(
        await SessionCipher.fromKey(Uint8List(32)),
      );
      final assembly = ControlFragments();
      Frame? complete;
      for (final part in parts.reversed) {
        final sealed = await sender.seal(part);
        expect(sealed.encode().length, lessThanOrEqualTo(Frame.maxTotalSize));
        complete = assembly.accept(await receiver.open(sealed), DateTime.now());
      }
      expect(complete!.payload, payload);
      expect(() => complete!.encode(), throwsStateError);
      final roster = RosterPayload.decode(complete.payload)!;
      expect(roster.members, hasLength(16));
      expect(roster.members.last.memberId, 16);
      expect(
        roster.members.every((member) => !member.nickname.contains('\uFFFD')),
        true,
      );
      expect(
        RosterPayload.decode(
          Uint8List.fromList(payload.take(payload.length - 1).toList()),
        ),
        isNull,
      );
    },
  );

  test(
    'partial, conflicting, expired and malformed messages never dispatch',
    () {
      var seq = 0;
      final parts = ControlFragments.split(
        type: FrameType.fusionState,
        senderId: 2,
        messageId: 1,
        payload: Uint8List(1000),
        maxPayload: 478,
        nextSeq: () => seq++,
      ).toList();
      final assembler = ControlFragments();
      final now = DateTime.now();
      expect(assembler.accept(parts.first, now), isNull);
      expect(
        assembler.accept(parts.first, now),
        isNull,
      ); // Identical duplicate.
      for (final part in parts.skip(1)) {
        expect(
          assembler.accept(part, now.add(const Duration(seconds: 13))),
          isNull,
        );
      }
      assembler.clear();
      expect(assembler.accept(parts.first, now), isNull);
      final changed = Uint8List.fromList(parts.first.payload)..[9] = 1;
      expect(
        assembler.accept(
          Frame(
            type: FrameType.controlFragment,
            senderId: 2,
            seq: 99,
            payload: changed,
          ),
          now,
        ),
        isNull,
      );
      for (final part in parts.skip(1)) {
        expect(assembler.accept(part, now), isNull);
      }
      final audio = Uint8List.fromList(parts.first.payload)
        ..[0] = FrameType.audio.value;
      expect(
        assembler.accept(
          Frame(
            type: FrameType.controlFragment,
            senderId: 2,
            seq: 100,
            payload: audio,
          ),
          now,
        ),
        isNull,
      );
      final tooLarge = Uint8List.fromList(parts.first.payload);
      ByteData.sublistView(tooLarge).setUint16(7, 65535);
      expect(
        assembler.accept(
          Frame(
            type: FrameType.controlFragment,
            senderId: 2,
            seq: 101,
            payload: tooLarge,
          ),
          now,
        ),
        isNull,
      );
    },
  );

  test('16-person transfer plan round-trips beyond a single wire frame', () {
    final plan = HostTransferPlan(
      successorId: 2,
      members: [
        for (var i = 2; i <= 16; i++)
          HostTransferMember(
            memberId: i,
            joinOrder: i,
            nickname: '$i${'声' * 20}',
            endpoint: '192.168.100.$i',
          ),
      ],
    );
    final bytes = HostTransferCodec.encode(plan);
    expect(bytes.length, greaterThan(Frame.maxPayloadSize));
    final decoded = HostTransferCodec.decode(bytes);
    expect(decoded.members, hasLength(15));
    expect(decoded.members.last.nickname, plan.members.last.nickname);
    expect(
      utf8.encode(decoded.members.last.nickname).length,
      lessThanOrEqualTo(64),
    );
  });

  test('member ring avoids full mesh and remains connected after one loss', () {
    final ids = [for (var id = 1; id <= 16; id++) id];
    final edges = <int, Set<int>>{for (final id in ids.skip(1)) id: {}};
    for (final id in edges.keys) {
      for (final peer in FusionPeerTopology.dialTargets(id, ids)) {
        edges[id]!.add(peer);
        edges[peer]!.add(id);
      }
    }
    expect(edges.values.every((neighbors) => neighbors.length == 2), true);
    for (final missing in edges.keys) {
      final seen = <int>{};
      final pending = [edges.keys.firstWhere((id) => id != missing)];
      while (pending.isNotEmpty) {
        final id = pending.removeLast();
        if (id == missing || !seen.add(id)) continue;
        pending.addAll(edges[id]!);
      }
      expect(seen, hasLength(14));
    }
  });
}
