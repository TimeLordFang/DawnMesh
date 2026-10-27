import 'package:dawn_mesh/core/audio/audio_io.dart';
import 'package:dawn_mesh/core/session/room_session.dart';
import 'package:dawn_mesh/core/protocol/frame.dart';
import 'package:dawn_mesh/core/protocol/frame_type.dart';
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
    BleL2capTransport.preferTextFallback.value = false;
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
    BleL2capTransport.preferTextFallback.value = false;
    messenger.setMockMethodCallHandler(methodChannel, null);
    for (final name in [dataEventChannel, scanEventChannel]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
  });

  test(
    'scan keeps a name on incomplete updates but clears it for a new PSM',
    () async {
      final transport = BleL2capTransport();
      addTearDown(transport.dispose);
      expect(await transport.startScan(), isTrue);
      Future<void> report(String? name, int psm, int members) async {
        messenger.handlePlatformMessage(
          scanEventChannel,
          const StandardMethodCodec().encodeSuccessEnvelope({
            'address': 'AA:BB:CC:DD:EE:01',
            'psm': psm,
            'roomName': name,
            'memberCount': members,
            'rssi': -40,
          }),
          (_) {},
        );
        await _until(
          () =>
              transport.currentRooms.isNotEmpty &&
              transport.currentRooms.single.memberCount == members,
        );
      }

      await report('完整房间名😀', 129, 1);
      await report('蓝牙房', 129, 2);
      expect(transport.currentRooms.single.roomName, '完整房间名😀');
      await report(null, 129, 3);
      expect(transport.currentRooms.single.roomName, '完整房间名😀');
      await report('  ', 130, 4);
      expect(transport.currentRooms.single.roomName, '蓝牙房');
    },
  );

  test('explicit compatibility test selects GATT only and disabling restores L2CAP', () async {
    final room = DiscoveredBleRoom(
      address: 'test-peer',
      roomName: 'test',
      psm: 129,
      memberCount: 1,
      rssi: -40,
      lastSeen: DateTime.now(),
    );
    final transport = BleL2capTransport();
    addTearDown(transport.dispose);
    BleL2capTransport.preferTextFallback.value = true;
    expect(await transport.connectToHost(room), true);
    expect(transport.textOnly, true);
    expect(
      calls.where((c) => c.method.startsWith('connect')).map((c) => c.method),
      ['connectGatt'],
    );
    await transport.stop();
    calls.clear();
    BleL2capTransport.preferTextFallback.value = false;
    expect(await transport.connectToHost(room), true);
    expect(transport.textOnly, false);
    expect(
      calls.where((c) => c.method.startsWith('connect')).map((c) => c.method),
      ['connectL2cap'],
    );
  });

  test('failed L2CAP falls back to text without opening the microphone or sending bulk data', () async {
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      return call.method != 'connectL2cap';
    });
    final transport = BleL2capTransport();
    final room = DiscoveredBleRoom(
      address: 'AA:BB:CC:DD:EE:01',
      roomName: '备用通道',
      psm: 129,
      memberCount: 1,
      rssi: -40,
      lastSeen: DateTime.now(),
    );
    expect(await transport.connectToHost(room), true);
    expect(transport.textOnly, true);
    expect(
      calls.where((c) => c.method.startsWith('connect')).map((c) => c.method),
      ['connectL2cap', 'connectGatt'],
    );
    final audio = MockAudioIo();
    final session = RoomSession(audioIo: audio, selfNickname: 'Client');
    session.attachTransport(transport, reconnect: () async => false);
    addTearDown(session.dispose);
    await session.startAudio();
    session.setPtt(true);
    expect(audio.isRecording, false);
    expect(session.isPttPressed, false);
    final wire = Frame(
      type: FrameType.sealed,
      senderId: 2,
      seq: 1,
      payload: Uint8List(32),
    );
    calls.clear();
    transport.sendPayload(wire, originalType: FrameType.audio);
    transport.sendPayload(wire, originalType: FrameType.chatImage);
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((c) => c.method == 'sendL2capData'), isEmpty);
    transport.sendPayload(wire, originalType: FrameType.chat);
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((c) => c.method == 'sendL2capData'), hasLength(1));
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
    final connects = calls
        .where((call) => call.method == 'connectL2cap')
        .toList();
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
