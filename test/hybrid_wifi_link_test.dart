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
}
