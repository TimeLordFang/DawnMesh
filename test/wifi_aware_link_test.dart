import 'dart:async';

import 'package:dawn_mesh/core/transport/wifi_aware_link.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('dev.dawnmesh.intercom/wifi_aware');
  const eventName = 'dev.dawnmesh.intercom/wifi_aware_events';
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'capabilities') {
        return {'supported': true, 'available': true};
      }
      if (call.method == 'start') return {'started': true, 'status': 'waiting'};
      return null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel(eventName),
      (_) async => null,
    );
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(const MethodChannel(eventName), null);
  });
  Future<void> event(Map<String, dynamic> data) async {
    messenger.handlePlatformMessage(
      eventName,
      const StandardMethodCodec().encodeSuccessEnvelope(data),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'unsupported hardware cannot start or alter existing connections',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return {'supported': false, 'reason': 'unsupported'};
      });
      var opened = 0;
      final link = WifiAwareLink(
        localPort: 8991,
        roomId: 'room',
        isHost: () => true,
        connect: (_) async {
          opened++;
          return true;
        },
      );
      await link.start();
      expect(link.active, false);
      expect(opened, 0);
      expect(calls.any((call) => call.method == 'start'), false);
      await link.close();
    },
  );
  test(
    'stale native events are ignored; simultaneous accelerators remain bounded',
    () async {
      final gate = Completer<bool>();
      var opened = 0;
      final link = WifiAwareLink(
        localPort: 8991,
        roomId: 'room',
        isHost: () => false,
        connect: (_) {
          opened++;
          return gate.future;
        },
      );
      await link.start();
      await event({'owner': 'stale', 'type': 'endpoint', 'port': 1234});
      expect(opened, 0);
      for (var i = 0; i < 10; i++) {
        await event({
          'owner': link.owner,
          'type': 'endpoint',
          'port': 1234 + i,
        });
      }
      expect(opened, 4);
      gate.complete(false);
      await Future<void>.delayed(Duration.zero);
      expect(link.status, contains('原连接继续'));
      await link.stop();
      expect(link.active, false);
      await link.close();
    },
  );
  test('closing during system setup cannot revive a departed room', () async {
    final gate = Completer<Map<String, dynamic>>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'capabilities') return {'supported': true};
      if (call.method == 'start') return gate.future;
      return null;
    });
    final link = WifiAwareLink(
      localPort: 8991,
      roomId: 'room',
      isHost: () => false,
      connect: (_) async => true,
    );
    final starting = link.start();
    while (!calls.any((call) => call.method == 'start')) {
      await Future<void>.delayed(Duration.zero);
    }
    await link.close();
    gate.complete({'started': true});
    await starting;
    expect(link.active, false);
    expect(calls.last.method, 'stop');
    expect(calls.last.arguments['owner'], link.owner);
  });
}
