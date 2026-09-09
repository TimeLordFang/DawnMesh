import 'package:dawn_mesh/core/transport/ble_l2cap_transport.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('dev.dawnmesh.intercom/ble_l2cap');
  const dataEventChannel = 'dev.dawnmesh.intercom/ble_l2cap_data';
  const scanEventChannel = 'dev.dawnmesh.intercom/ble_l2cap_scan';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      return true;
    });
    for (final name in [dataEventChannel, scanEventChannel]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
        calls.add(call);
        return null;
      });
    }
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
    for (final name in [dataEventChannel, scanEventChannel]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
  });

  test('reconnect rescans and uses refreshed BLE address and PSM', () async {
    final transport = BleL2capTransport();
    addTearDown(transport.dispose);
    final original = DiscoveredBleRoom(
      address: 'AA:BB:CC:DD:EE:01',
      roomName: '测试房间',
      psm: 129,
      memberCount: 2,
      rssi: -45,
      lastSeen: DateTime.now(),
    );
    expect(await transport.connectToHost(original), isTrue);

    final reconnecting = transport.reconnect();
    await _until(() => calls.any((call) => call.method == 'startScan'));
    messenger.handlePlatformMessage(
      scanEventChannel,
      const StandardMethodCodec().encodeSuccessEnvelope({
        'address': 'AA:BB:CC:DD:EE:99',
        'psm': 177,
        'roomName': '测试房间',
        'memberCount': 2,
        'rssi': -51,
      }),
      (_) {},
    );

    expect(await reconnecting, isTrue);
    final connects =
        calls.where((call) => call.method == 'connectL2cap').toList();
    expect(connects, hasLength(2));
    expect(connects.last.arguments['address'], 'AA:BB:CC:DD:EE:99');
    expect(connects.last.arguments['psm'], 177);
  });
}

Future<void> _until(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
