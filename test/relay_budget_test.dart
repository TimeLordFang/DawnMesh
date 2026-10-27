import 'dart:typed_data';

import 'package:dawn_mesh/core/protocol/frame.dart';
import 'package:dawn_mesh/core/protocol/frame_type.dart';
import 'package:dawn_mesh/core/protocol/relay_budget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final type in [
    FrameType.sealed,
    FrameType.handshakeHello,
    FrameType.handshakeConfirm,
  ]) {
    test(
      '$type delayed cycles terminate even after duplicate cache expiry',
      () {
        final initial = Frame(
          type: type,
          senderId: 2,
          seq: (8 << 8) | 37,
          payload: Uint8List.fromList([3, 0, 0, 0, 1, 8, 99]),
        );
        var packet = initial;
        final key = RelayBudget.cacheKeyBytes(initial.encode());
        // Simulate a cycle with no surviving dedup state: only the wire budget
        // remains. Each of eight honest hops consumes one unit.
        for (var hop = 0; hop < RelayBudget.maximum; hop++) {
          packet = RelayBudget.forward(packet)!;
          expect(RelayBudget.remaining(packet), 7 - hop);
          expect(RelayBudget.cacheKeyBytes(packet.encode()), key);
          expect(packet.payload.last, 99);
        }
        expect(RelayBudget.forward(packet), isNull);
        expect(
          RelayBudget.remaining(initial),
          8,
          reason: 'do not mutate other routes',
        );
      },
    );
  }
  test('invalid and legacy envelopes do not bypass the forwarding budget', () {
    for (final payload in [
      <int>[],
      [2, 0, 0, 0, 0, 8],
      [3, 0, 0, 0, 0, 9],
    ]) {
      expect(
        RelayBudget.forward(
          Frame(
            type: FrameType.sealed,
            senderId: 1,
            seq: 1,
            payload: Uint8List.fromList(payload),
          ),
        ),
        isNull,
      );
    }
  });
}
