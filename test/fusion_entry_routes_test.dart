import 'dart:async';
import 'dart:io';

import 'package:dawn_mesh/core/audio/audio_io.dart';
import 'package:dawn_mesh/core/fusion/fusion_identity.dart';
import 'package:dawn_mesh/core/fusion/fusion_route_race.dart';
import 'package:dawn_mesh/core/fusion/fusion_transport.dart';
import 'package:dawn_mesh/core/security/room_invite.dart';
import 'package:dawn_mesh/core/session/room_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> until(bool Function() test) async {
  final deadline = DateTime.now().add(const Duration(seconds: 6));
  while (!test()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Fusion admission');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  const apple = MethodChannel('dev.dawnmesh.intercom/apple_peer');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(apple, null));

  Future<(RoomSession, FusionTransport)> node(
    FusionIdentity identity, {
    bool host = false,
  }) async {
    final session = RoomSession(
      audioIo: MockAudioIo(),
      selfNickname: host ? '房主' : '成员',
      mode: RoomMode.fusion,
    );
    final link = FusionTransport(
      roomId: identity.roomId,
      roomName: identity.name,
      identity: host ? identity : null,
      localPort: 0,
      advertise: false,
    );
    await session.protectWithInvite(RoomInvite.parse('1234'));
    session.attachTransport(link, reconnect: link.reconnect);
    addTearDown(session.dispose);
    await link.start(session);
    if (host) await session.createRoom(startAudio: false);
    return (session, link);
  }

  test('Apple fusion route upgrades WebSocket, authenticates and exchanges encrypted chat', () async {
    final identity = await FusionIdentity.create('苹果融合房');
    final (host, server) = await node(identity, host: true);
    final (guest, client) = await node(identity);
    final closed = <String>[];
    messenger.setMockMethodCallHandler(apple, (call) async {
      if (call.method == 'open') {
        expect(call.arguments['service'], 'scoped-apple-endpoint');
        return {'port': server.boundPort, 'connectionId': 'proxy-1'};
      }
      closed.add(call.arguments['connectionId'] as String);
      return null;
    });
    expect(
      await client.connectLocal(
        '127.0.0.1',
        port: 9,
        applePeerService: 'scoped-apple-endpoint',
      ),
      isTrue,
    );
    await guest.joinRoom(startAudio: false);
    await until(() => guest.state == RoomState.inRoom);
    await guest.sendChat('经点对点代理入房');
    await until(
      () => host.chatMessages.any((message) => message.text == '经点对点代理入房'),
    );
    expect(guest.sessionToken, isNot(Uint8List(16)));
    await client.stop();
    await until(() => closed.length == 1);
    expect(closed, ['proxy-1']);
  });

  test('a late Apple open is closed after cancellation instead of reviving the room', () async {
    final (_, client) = await node(await FusionIdentity.create('取消'));
    final entered = Completer<void>();
    final pending = Completer<Map<String, Object>>();
    final closed = <String>[];
    messenger.setMockMethodCallHandler(apple, (call) async {
      if (call.method == 'open') {
        entered.complete();
        return pending.future;
      }
      closed.add(call.arguments['connectionId'] as String);
      return null;
    });
    final connecting = client.connectLocal(
      '127.0.0.1',
      applePeerService: 'pending',
    );
    await entered.future;
    await client.stop();
    pending.complete({'port': 9, 'connectionId': 'late-proxy'});
    expect(await connecting, isFalse);
    expect(client.peerCount, 0);
    expect(closed, ['late-proxy']);
  });

  test('cloud candidate rescues an indefinitely stalled local dial', () async {
    final local = Completer<bool>();
    var cloudCalls = 0;
    expect(
      await FusionRouteRace.connect(
        local: [() => local.future],
        cloud: () async {
          cloudCalls++;
          return true;
        },
        cloudDelay: Duration.zero,
      ),
      isTrue,
    );
    expect(cloudCalls, 1);
    local.complete(false);
  });

  test(
    'finished local admission avoids a needless delayed cloud dial',
    () async {
      var finished = false;
      var cloudCalls = 0;
      expect(
        await FusionRouteRace.connect(
          local: [() async => true],
          cloud: () async {
            cloudCalls++;
            return true;
          },
          finished: () => finished,
          cloudDelay: const Duration(milliseconds: 30),
        ),
        isTrue,
      );
      finished = true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(cloudCalls, 0);
    },
  );

  test('an open but silent local route cannot block admission through a second route', () async {
    final identity = await FusionIdentity.create('兜底入房');
    final (host, server) = await node(identity, host: true);
    final (guest, client) = await node(identity);
    final stableIdentity = Uint8List.fromList(guest.sessionToken);
    final blackhole = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    blackhole.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((_) {});
    });
    addTearDown(() async {
      for (final socket in sockets) {
        unawaited(socket.close());
      }
      await blackhole.close(force: true);
    });
    var admitted = false;
    expect(
      await FusionRouteRace.connect(
        local: [() => client.connectLocal('127.0.0.1', port: blackhole.port)],
        cloud: () => client.connectLocal('127.0.0.1', port: server.boundPort),
        finished: () => admitted,
        cloudDelay: const Duration(milliseconds: 80),
      ),
      isTrue,
    );
    await guest.joinRoom(startAudio: false);
    await until(() => guest.state == RoomState.inRoom);
    admitted = true;
    expect(guest.sessionToken, stableIdentity);
    expect(host.members.length, 2);
  });
}
