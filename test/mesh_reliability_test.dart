import 'dart:async';
import 'dart:typed_data';

import 'package:dawn_mesh/core/transport/bounded_packet_writer.dart';
import 'package:dawn_mesh/core/session/reliable_chat.dart';
import 'package:dawn_mesh/core/protocol/frame.dart';
import 'package:dawn_mesh/core/protocol/frame_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'slow link bounds memory, expires audio, preserves control order',
    () async {
      var now = DateTime(2026);
      final gate = Completer<void>();
      final written = <int>[];
      final writer = BoundedPacketWriter(
        capacity: 3,
        now: () => now,
        write: (bytes) async {
          written.add(bytes.first);
          if (written.length == 1) await gate.future;
        },
        onFailure: (error) => fail('$error'),
      );
      writer.send(Uint8List.fromList([1]));
      await Future<void>.delayed(Duration.zero);
      for (var i = 0; i < 100; i++) {
        writer.send(Uint8List.fromList([10 + i]), realtime: true);
        expect(writer.pending, lessThanOrEqualTo(3));
      }
      writer.send(Uint8List.fromList([2]));
      now = now.add(const Duration(seconds: 1));
      gate.complete();
      await writer.flush();
      expect(written, [1, 2]);
      expect(writer.droppedAudio, 100);
      writer.close();
    },
  );

  test('control saturation fails only that link instead of silently losing control', () async {
    final errors = <Object>[];
    final gate = Completer<void>();
    final writer = BoundedPacketWriter(
      capacity: 2,
      write: (_) => gate.future,
      onFailure: errors.add,
    );
    writer.send(Uint8List(1));
    writer.send(Uint8List(1));
    expect(writer.send(Uint8List(1)), false);
    expect(errors, hasLength(1));
    expect(writer.pending, 0);
    gate.complete();
    await writer.flush();
  });

  test('partition heals, duplicate frames ACK again, group receipt waits for all peers', () {
    var now = DateTime(2026);
    var seq = 0;
    final wires = <(int, Frame)>[];
    final engines = <int, ReliableChat>{};
    for (var id = 1; id <= 3; id++) {
      final sender = id;
      engines[id] = ReliableChat(
        selfId: () => sender,
        members: () => {1, 2, 3},
        nextSeq: () => seq++,
        changed: () {},
        now: () => now,
        emit: (f) => wires.add((sender, f)),
      );
    }
    void pump({int? partition}) {
      var budget = 1000;
      while (wires.isNotEmpty) {
        expect(--budget, greaterThan(0), reason: 'relay/ACK storm');
        final (source, frame) = wires.removeAt(0);
        for (final target in engines.keys) {
          if (source == target || source == partition || target == partition) {
            continue;
          }
          if (frame.type == FrameType.chatControl) {
            engines[target]!.handle(frame);
          } else {
            engines[target]!.received(frame);
          }
        }
      }
    }

    for (var i = 0; i < 3; i++) {
      for (final e in engines.values) {
        e.tick();
      }
      pump();
    }
    final f = Frame(
      type: FrameType.chat,
      senderId: 1,
      seq: 700,
      payload: Uint8List.fromList([1, 2, 3]),
    );
    engines[1]!.remember(f, messageId: 'm');
    wires.add((1, f));
    pump(partition: 3);
    expect(engines[1]!.status('m'), ChatDelivery.pending);
    now = now.add(const Duration(seconds: 7));
    engines[1]!.tick();
    pump();
    expect(engines[1]!.status('m'), ChatDelivery.delivered);
    // A duplicate cannot cause an infinite ACK cycle.
    wires.add((1, f));
    pump();
    expect(engines[1]!.status('m'), ChatDelivery.delivered);
  });

  test('whole-note ACK policy does not starve later missing voice fragments', () {
    var now = DateTime(2026);
    final sent = <Frame>[];
    final engine = ReliableChat(
      selfId: () => 1,
      members: () => {1, 2},
      emit: sent.add,
      changed: () {},
      nextSeq: () => 1,
      now: () => now,
    );
    engine.handle(
      Frame(
        type: FrameType.chatControl,
        senderId: 2,
        seq: 1,
        payload: Uint8List.fromList([1, 1, 0, 0]),
      ),
    );
    for (var i = 0; i < 80; i++) {
      engine.remember(
        Frame(
          type: FrameType.voiceNote,
          senderId: 1,
          seq: i,
          payload: Uint8List.fromList([i]),
        ),
        messageId: 'note',
      );
    }
    // The recipient confirms only after full assembly. A fixed queue prefix
    // would endlessly retry early chunks and never reach a missing final chunk.
    for (var tick = 0; tick < 10; tick++) {
      now = now.add(const Duration(seconds: 7));
      engine.tick();
    }
    final repairs = sent
        .where((f) => f.type == FrameType.voiceNote)
        .map((f) => f.seq)
        .toList();
    expect(repairs, hasLength(80));
    expect(repairs.toSet(), hasLength(80));
    expect(engine.status('note'), ChatDelivery.pending);
  });

  test('media quota evicts whole notes and never confirms a partially forgotten note', () {
    final engine = ReliableChat(
      selfId: () => 1,
      members: () => {1, 2},
      emit: (_) {},
      changed: () {},
      nextSeq: () => 1,
    );
    engine.handle(
      Frame(
        type: FrameType.chatControl,
        senderId: 2,
        seq: 1,
        payload: Uint8List.fromList([1, 1, 0, 0]),
      ),
    );
    for (var i = 0; i < 600; i++) {
      engine.remember(
        Frame(
          type: FrameType.voiceNote,
          senderId: 1,
          seq: i,
          payload: Uint8List.fromList([i & 255]),
        ),
        messageId: i < 300 ? 'first' : 'second',
      );
    }
    expect(engine.status('first'), ChatDelivery.failed);
    expect(engine.status('second'), ChatDelivery.pending);
    engine.forgetMessage('first');
    expect(engine.status('first'), isNull);
  });

  test('old clients without capability stay sent, never falsely delivered', () {
    final engine = ReliableChat(
      selfId: () => 1,
      members: () => {1, 2},
      emit: (_) {},
      changed: () {},
      nextSeq: () => 1,
    );
    engine.remember(
      Frame(type: FrameType.chat, senderId: 1, seq: 1, payload: Uint8List(1)),
      messageId: 'old',
    );
    expect(engine.status('old'), ChatDelivery.sent);
  });
}
