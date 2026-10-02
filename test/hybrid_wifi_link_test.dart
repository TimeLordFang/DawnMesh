import 'package:dawn_mesh/core/internet/hybrid_wifi_link.dart';
import 'package:dawn_mesh/core/transport/wifi_direct_manager.dart';
import 'package:dawn_mesh/core/transport/wifi_direct_credentials.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const credentials = WifiDirectCredentials(
    networkName: 'DIRECT-ab-test',
    passphrase: 'test-password',
  );
  WifiP2pConnectionInfo state(bool formed, bool owner) => WifiP2pConnectionInfo(
    isConnected: formed,
    isGroupOwner: owner,
    groupFormed: formed,
    groupOwnerAddress: formed ? '192.168.49.1' : '',
  );
  test('guest waits for authenticated owner readiness then joins and retries without interaction', () async {
    var joins = 0;
    var now = DateTime(2026);
    var formed = false;
    final link = HybridWifiLink(
      selfId: 'guest',
      hostId: 'host',
      credentials: credentials,
      signal: (_) async {},
      info: () async => state(formed, false),
      create: (_) async {
        fail('guest created group');
      },
      join: (_) async {
        joins++;
        return true;
      },
      disconnect: () async => true,
      now: () => now,
    );
    await link.tick();
    expect(joins, 0);
    final ready = {'kind': 'wifi_ready', ...credentials.toMap()};
    link.receive('impostor', ready);
    await link.tick();
    expect(joins, 0);
    link.receive('host', ready);
    await link.tick();
    expect(joins, 1);
    await link.tick();
    expect(joins, 1);
    formed = true;
    await link.tick();
    expect(joins, 1);
    formed = false;
    now = now.add(const Duration(seconds: 16));
    await link.tick();
    expect(joins, 1); // Expired owner announcement cannot trigger joining.
    link.receive('host', ready);
    await link.tick();
    expect(joins, 2);
    await link.close();
  });
  test(
    'host announces only after group is actually ready, and tears it down',
    () async {
      var formed = false, creates = 0, disconnects = 0;
      final signals = <Map<String, dynamic>>[];
      final link = HybridWifiLink(
        selfId: 'host',
        hostId: 'host',
        credentials: credentials,
        signal: (d) async => signals.add(d),
        info: () async => state(formed, true),
        create: (_) async {
          creates++;
          return true;
        },
        join: (_) async => false,
        disconnect: () async {
          disconnects++;
          return true;
        },
      );
      await link.tick();
      expect(creates, 1);
      expect(signals, isEmpty);
      formed = true;
      await link.tick();
      expect(signals.single['kind'], 'wifi_ready');
      await link.close();
      expect(disconnects, 1);
    },
  );
  test('existing unrelated group is neither advertised nor removed', () async {
    final link = HybridWifiLink(
      selfId: 'host',
      hostId: 'host',
      credentials: credentials,
      signal: (_) async {
        fail('advertised unrelated group');
      },
      info: () async => state(true, true),
      create: (_) async => false,
      join: (_) async => false,
      disconnect: () async {
        fail('removed unrelated group');
      },
    );
    await link.tick();
    await link.close();
  });
  test(
    'missing permission reports a useful state and recovers on the next poll',
    () async {
      var ready = 'permission', creates = 0;
      final link = HybridWifiLink(
        selfId: 'host',
        hostId: 'host',
        credentials: credentials,
        availability: () async => ready,
        signal: (_) async {},
        info: () async => state(false, false),
        create: (_) async {
          creates++;
          return true;
        },
        join: (_) async => false,
        disconnect: () async => true,
      );
      await link.tick();
      expect(creates, 0);
      expect(link.status, contains('权限'));
      ready = 'wifi_off';
      await link.tick();
      expect(creates, 0);
      expect(link.status, contains('打开 Wi-Fi'));
      ready = 'ready';
      await link.tick();
      expect(creates, 1);
      expect(link.status, contains('正在建立'));
      await link.close();
    },
  );
  test('failed group creation retries under one owner and eventually announces readiness', () async {
    var attempts = 0, formed = false;
    var now = DateTime(2026);
    final signals = <Map<String, dynamic>>[];
    final link = HybridWifiLink(
      selfId: 'host',
      hostId: 'host',
      credentials: credentials,
      signal: (data) async => signals.add(data),
      info: () async => state(formed, true),
      create: (_) async => ++attempts > 1,
      join: (_) async => false,
      disconnect: () async => true,
      now: () => now,
    );
    await link.tick();
    expect(link.status, contains('重试'));
    now = now.add(const Duration(seconds: 16));
    await link.tick();
    formed = true;
    await link.tick();
    expect(signals.single['kind'], 'wifi_ready');
    expect(link.status, contains('直连入口已就绪'));
    expect(link.status, isNot(contains('正在协商语音')));
    await link.close();
  });
  test(
    'a surviving group for this exact room is adopted and advertised',
    () async {
      final signals = <Map<String, dynamic>>[];
      var removed = false;
      final link = HybridWifiLink(
        selfId: 'host',
        hostId: 'host',
        credentials: credentials,
        signal: (data) async => signals.add(data),
        info: () async => WifiP2pConnectionInfo(
          isConnected: true,
          isGroupOwner: true,
          groupFormed: true,
          groupOwnerAddress: '192.168.49.1',
          networkName: credentials.networkName,
        ),
        create: (_) async {
          fail('must adopt the matching existing group');
        },
        join: (_) async => false,
        disconnect: () async {
          removed = true;
          return true;
        },
      );
      await link.tick();
      expect(signals.single['kind'], 'wifi_ready');
      await link.close();
      expect(removed, isTrue);
    },
  );
}
