import 'dart:async';
import 'dart:io';

import 'package:dawn_mesh/core/fusion/fusion_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  Future<(FusionTransport, HttpServer)> setup() async {
    final transport = FusionTransport(
      roomId: 'connection-test',
      roomName: 'Test',
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(transport.dispose);
    addTearDown(() => server.close(force: true));
    return (transport, server);
  }

  test('concurrent local callers share one handshake and its result', () async {
    final (transport, server) = await setup();
    final arrived = Completer<void>();
    final release = Completer<void>();
    final sockets = <WebSocket>[];
    var requests = 0;
    server.listen((request) async {
      requests++;
      if (!arrived.isCompleted) arrived.complete();
      await release.future;
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((_) {});
    });
    addTearDown(() async {
      for (final socket in sockets) {
        unawaited(socket.close());
      }
    });
    final first = transport.connectLocal('127.0.0.1', port: server.port);
    await arrived.future;
    final second = transport.connectLocal('127.0.0.1', port: server.port);
    release.complete();
    expect(await Future.wait([first, second]), [true, true]);
    expect(requests, 1);
    expect(transport.peerCount, 1);
  });

  test(
    'a busy local peer can finish its handshake beyond four seconds',
    () async {
      final (transport, server) = await setup();
      final sockets = <WebSocket>[];
      addTearDown(() async {
        for (final socket in sockets) {
          unawaited(socket.close());
        }
      });
      server.listen((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 4500));
        try {
          final socket = await WebSocketTransformer.upgrade(request);
          sockets.add(socket);
          socket.listen((_) {});
        } catch (_) {
          // A prematurely cancelled client is reported by the assertion below.
        }
      });
      expect(
        await transport.connectLocal('127.0.0.1', port: server.port),
        true,
      );
      expect(transport.peerCount, 1);
    },
  );

  test('stopping cancels a pending local HTTP upgrade', () async {
    final (transport, server) = await setup();
    final arrived = Completer<void>();
    server.listen((request) {
      request.response.done.ignore();
      arrived.complete();
    });
    final connecting = transport.connectLocal('127.0.0.1', port: server.port);
    await arrived.future;
    await transport.stop();
    expect(await connecting.timeout(const Duration(seconds: 1)), false);
    expect(transport.peerCount, 0);
  });

  test('a timed out local HTTP upgrade releases its connection', () async {
    final transport = FusionTransport(
      roomId: 'connection-test',
      roomName: 'Test',
    );
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(transport.dispose);
    addTearDown(server.close);
    final disconnected = Completer<void>();
    server.listen((socket) {
      addTearDown(socket.destroy);
      socket.listen((_) {}, onDone: () => disconnected.complete());
    });
    expect(await transport.connectLocal('127.0.0.1', port: server.port), false);
    await disconnected.future.timeout(const Duration(seconds: 1));
    expect(transport.peerCount, 0);
  });
}
