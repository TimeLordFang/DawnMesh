import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/protocol/frame.dart';
import 'package:sunset_ripple/core/protocol/frame_type.dart';
import 'package:sunset_ripple/core/transport/lan_transport.dart';

void main() {
  test(
    'client cannot inject host-only commands over TCP or control frames over UDP',
    () async {
      final host = LanTransport();
      expect(await host.startHost(), isTrue);
      addTearDown(host.dispose);
      final tcp = await Socket.connect(
        InternetAddress.loopbackIPv4,
        LanTransport.controlPort,
      );
      final udp = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() {
        tcp.destroy();
        udp.close();
      });
      final received = <Frame>[];
      final completed = Completer<void>();
      final sub = host.incoming.listen((frame) {
        received.add(frame);
        if (frame.type == FrameType.heartbeat && !completed.isCompleted) {
          completed.complete();
        }
      });
      addTearDown(sub.cancel);
      Frame frame(FrameType type) =>
          Frame(type: type, senderId: 2, seq: 1, payload: Uint8List(0));
      for (final type in [
        FrameType.roster,
        FrameType.hostHandover,
        FrameType.hostAnnounce,
        FrameType.chatSync,
      ]) {
        tcp.add(frame(type).encode());
      }
      tcp.add(frame(FrameType.heartbeat).encode());
      await tcp.flush();
      await completed.future.timeout(const Duration(seconds: 2));
      expect(received.map((f) => f.type), [FrameType.heartbeat]);
      host.updateKnownMemberIds({2});
      udp.send(
        frame(FrameType.roster).encode(),
        InternetAddress.loopbackIPv4,
        LanTransport.audioPort,
      );
      udp.send(
        frame(FrameType.heartbeat).encode(),
        InternetAddress.loopbackIPv4,
        LanTransport.audioPort,
      );
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (!host.peerEndpoints.containsKey(2) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(host.peerEndpoints.containsKey(2), isTrue);
      expect(received.map((f) => f.type), [FrameType.heartbeat]);
    },
  );
}
