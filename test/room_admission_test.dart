import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:dawn_mesh/core/protocol/frame.dart';
import 'package:dawn_mesh/core/protocol/frame_type.dart';
import 'package:dawn_mesh/core/security/room_admission.dart';
import 'package:dawn_mesh/core/security/session_handshake.dart';
import 'package:dawn_mesh/core/security/spake2.dart';

void main() {
  test(
    'traffic key is released only after confirmation, and differs across rooms',
    () async {
      final hostFrames = <Frame>[];
      final guestFrames = <Frame>[];
      late SecureFrameCodec hostCodec;
      SecureFrameCodec? guestCodec;
      final host = RoomAdmission(
        passwordScalar: BigInt.one,
        token: Uint8List(16),
        send: hostFrames.add,
        onReady: (c) async {
          hostCodec = c;
        },
      );
      final guest = RoomAdmission(
        passwordScalar: BigInt.one,
        token: Uint8List(16)..[0] = 3,
        send: guestFrames.add,
        onReady: (c) async {
          guestCodec = c;
        },
      );
      addTearDown(host.close);
      addTearDown(guest.close);
      await host.startHost();
      guest.startClient();
      await host.handle(guestFrames.single);
      expect(hostFrames.single.payload[1], 2); // PAKE response, no traffic key.
      expect(guestCodec, isNull);
      await guest.handle(hostFrames.single);
      expect(guestCodec, isNull);
      await host.handle(guestFrames.last);
      expect(hostFrames.last.payload[1], 4);
      await guest.handle(hostFrames.last);
      expect(guestCodec, isNotNull);
      final plain = Frame(
        type: FrameType.audio,
        senderId: 1,
        seq: 1,
        payload: Uint8List.fromList([1]),
      );
      expect((await guestCodec!.open(await hostCodec.seal(plain))).payload, [
        1,
      ]);
      late SecureFrameCodec otherCodec;
      final other = RoomAdmission(
        passwordScalar: BigInt.one,
        token: Uint8List(16),
        send: (_) {},
        onReady: (c) async {
          otherCodec = c;
        },
      );
      addTearDown(other.close);
      await other.startHost();
      await expectLater(
        otherCodec.open(await hostCodec.seal(plain)),
        throwsA(anything),
      );
    },
  );

  test(
    'host rate limit bounds online guesses and duplicate challenges',
    () async {
      final sent = <Frame>[];
      final host = RoomAdmission(
        passwordScalar: BigInt.one,
        token: Uint8List(16),
        send: sent.add,
        onReady: (_) async {},
      );
      addTearDown(host.close);
      await host.startHost();
      final validPoint = Spake2(isA: true, passwordScalar: BigInt.one).message;
      for (var i = 0; i < 20; i++) {
        final token = Uint8List(16)..[0] = i;
        final request = Frame(
          type: FrameType.handshakeHello,
          senderId: 0,
          seq: 0,
          payload: Uint8List.fromList([2, 1, ...token, ...validPoint]),
        );
        await host.handle(request);
        await host.handle(
          request,
        ); // Duplicate must not create another challenge.
        await host.handle(
          Frame(
            type: FrameType.handshakeConfirm,
            senderId: 0,
            seq: 0,
            payload: Uint8List.fromList([2, 3, ...token, ...Uint8List(32)]),
          ),
        );
      }
      expect(sent.length, 10);
      expect(sent.every((f) => f.payload[1] == 2), isTrue); // No key grant.
    },
  );

  test('client can repeat PAKE after a physical reconnection', () async {
    final hostFrames = <Frame>[];
    final guestFrames = <Frame>[];
    final guestCodecs = <SecureFrameCodec>[];
    late SecureFrameCodec hostCodec;
    final host = RoomAdmission(
      passwordScalar: BigInt.from(123456),
      token: Uint8List(16),
      send: hostFrames.add,
      onReady: (codec) async => hostCodec = codec,
    );
    final guest = RoomAdmission(
      passwordScalar: BigInt.from(123456),
      token: Uint8List(16)..[0] = 7,
      send: guestFrames.add,
      onReady: (codec) async => guestCodecs.add(codec),
    );
    addTearDown(host.close);
    addTearDown(guest.close);
    await host.startHost();

    Future<void> authenticate() async {
      guest.startClient();
      await host.handle(guestFrames.removeAt(0));
      await guest.handle(hostFrames.removeAt(0));
      await host.handle(guestFrames.removeAt(0));
      await guest.handle(hostFrames.removeAt(0));
    }

    await authenticate();
    final captured = await hostCodec.seal(
      Frame(
        type: FrameType.audio,
        senderId: 1,
        seq: 1,
        payload: Uint8List.fromList([42]),
      ),
    );
    await guestCodecs.last.open(captured);
    final outgoing = await guestCodecs.last.seal(
      Frame(
        type: FrameType.audio,
        senderId: 2,
        seq: 1,
        payload: Uint8List.fromList([7]),
      ),
    );
    await hostCodec.open(outgoing);
    // An interrupted fresh handshake must not discard the traffic session.
    guest.startClient();
    guestFrames.clear();
    await authenticate();
    expect(guestCodecs, hasLength(2));
    expect(identical(guestCodecs.first, guestCodecs.last), isTrue);
    await expectLater(guestCodecs.last.open(captured), throwsStateError);
    final fresh = await hostCodec.seal(
      Frame(
        type: FrameType.audio,
        senderId: 1,
        seq: 2,
        payload: Uint8List.fromList([43]),
      ),
    );
    expect((await guestCodecs.last.open(fresh)).payload, [43]);
    final nextOutgoing = await guestCodecs.last.seal(
      Frame(
        type: FrameType.audio,
        senderId: 2,
        seq: 2,
        payload: Uint8List.fromList([8]),
      ),
    );
    expect((await hostCodec.open(nextOutgoing)).payload, [8]);
    expect(nextOutgoing.payload.sublist(0, 8), outgoing.payload.sublist(0, 8));
    expect(ByteData.sublistView(nextOutgoing.payload).getUint32(8), 1);

    // A different host key must establish a new replay namespace.
    final oldCodec = guestCodecs.last;
    final replacementHost = RoomAdmission(
      passwordScalar: BigInt.from(123456),
      token: Uint8List(16),
      send: hostFrames.add,
      onReady: (codec) async => hostCodec = codec,
    );
    addTearDown(replacementHost.close);
    await replacementHost.startHost();
    guest.startClient();
    await replacementHost.handle(guestFrames.removeAt(0));
    await guest.handle(hostFrames.removeAt(0));
    await replacementHost.handle(guestFrames.removeAt(0));
    await guest.handle(hostFrames.removeAt(0));
    expect(identical(guestCodecs.last, oldCodec), isFalse);
    await expectLater(guestCodecs.last.open(captured), throwsA(anything));
    expect(
      (await guestCodecs.last.open(
        await hostCodec.seal(
          Frame(
            type: FrameType.audio,
            senderId: 1,
            seq: 1,
            payload: Uint8List.fromList([44]),
          ),
        ),
      )).payload,
      [44],
    );
  });
}
