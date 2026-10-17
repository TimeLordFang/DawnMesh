import 'dart:async';
import 'dart:io';

import 'package:dawn_mesh/core/transport/lan_discovery.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const channel = MethodChannel('dev.dawnmesh.intercom/bonjour');
  const eventChannel = MethodChannel('dev.dawnmesh.intercom/bonjour_events');
  const codec = StandardMethodCodec();
  late List<MethodCall> calls;

  Future<void> emit(Map<String, dynamic> event) async {
    final delivered = Completer<void>();
    binding.channelBuffers.push(
      eventChannel.name,
      codec.encodeSuccessEnvelope(event),
      (_) => delivered.complete(),
    );
    await delivered.future;
    await Future<void>.delayed(Duration.zero);
  }

  Map<String, dynamic> room(
    String id, {
    String service = 'apple-room',
    int port = 51432,
  }) => {
    'id': id,
    'service': service,
    'type': 'room',
    'magic': LanRoomDiscovery.magicHeader,
    'roomId': 'ios-room',
    'roomName': 'iPhone 房间 🌅',
    'hostNickname': '房主',
    'address': '192.168.1.42',
    'port': port,
    'members': 2,
  };

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'start' ? true : null;
    });
    messenger.setMockMethodCallHandler(eventChannel, (_) async => null);
  });
  tearDown(() async {
    await Future<void>.delayed(Duration.zero);
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(eventChannel, null);
  });

  LanRoomDiscovery discovery({String magic = LanRoomDiscovery.magicHeader}) {
    final value = LanRoomDiscovery(
      magic: magic,
      nativeDiscoveryEnabled: true,
      bindSocket: (_) async => throw const SocketException('UDP unavailable'),
    );
    addTearDown(() async {
      await value.stop();
      value.dispose();
    });
    return value;
  }

  test('DNS-SD discovers an iOS proxy port when UDP is unavailable', () async {
    final value = discovery();
    expect(await value.startListening(), isTrue);
    final id = calls.last.arguments['id'] as String;
    await emit(room(id));
    expect(value.currentRooms.single.roomName, 'iPhone 房间 🌅');
    expect(value.currentRooms.single.hostNickname, '房主');
    expect(value.currentRooms.single.port, 51432);
    expect(value.currentRooms.single.applePeerService, isNull);
    await emit(room(id, port: 51433));
    expect(value.currentRooms, hasLength(1));
    expect(value.currentRooms.single.port, 51433);
    await emit({'id': id, 'service': 'apple-room', 'type': 'removed'});
    expect(value.currentRooms, isEmpty);
  });

  test(
    'native advertisements carry full names, TCP port and membership',
    () async {
      final value = discovery();
      await value.startListening();
      value.startAdvertising(
        roomId: 'mine',
        roomName: '中文 🌅',
        hostNickname: '我的名字',
        tcpPort: 8988,
        getMemberCount: () => 3,
      );
      await Future<void>.delayed(Duration.zero);
      final args =
          calls.firstWhere((call) => call.method == 'advertise').arguments
              as Map;
      expect(args['roomName'], '中文 🌅');
      expect(args['hostNickname'], '我的名字');
      expect(args['port'], 8988);
      expect(args['members'], 3);
      await emit({...room(args['id'] as String), 'roomId': 'mine'});
      expect(value.currentRooms, isEmpty);
      await value.stop();
      expect(calls.any((call) => call.method == 'stopAdvertising'), isTrue);
      expect(calls.any((call) => call.method == 'stop'), isTrue);
    },
  );

  test(
    'Wi-Fi and fusion watchers isolate events and ignore late results',
    () async {
      final wifi = discovery();
      final fusion = discovery(magic: 'DAWN_MESH_FUSION_V1');
      await wifi.startListening();
      final wifiId = calls.last.arguments['id'] as String;
      await fusion.startListening();
      final fusionId = calls.last.arguments['id'] as String;
      await emit(room(wifiId));
      expect(wifi.currentRooms, hasLength(1));
      expect(fusion.currentRooms, isEmpty);
      await emit({...room(fusionId), 'magic': 'DAWN_MESH_FUSION_V1'});
      expect(fusion.currentRooms, hasLength(1));
      await wifi.stop();
      await emit(room(wifiId));
      expect(wifi.currentRooms, isEmpty);
      expect(fusion.currentRooms, hasLength(1));
    },
  );

  test(
    'untrusted DNS-SD metadata cannot bypass port validation or capacity',
    () async {
      final value = discovery();
      await value.startListening();
      final id = calls.last.arguments['id'] as String;
      await emit(room(id, port: 70000));
      expect(value.currentRooms, isEmpty);
      await emit({...room(id), 'address': 'not-an-address'});
      expect(value.currentRooms, isEmpty);
      for (var i = 0; i < LanRoomDiscovery.maxDiscoveredRooms + 10; i++) {
        await emit({...room(id, service: 'service-$i'), 'roomId': 'room-$i'});
      }
      expect(
        value.currentRooms.length,
        lessThanOrEqualTo(LanRoomDiscovery.maxDiscoveredRooms),
      );
    },
  );

  test('missing native plugin preserves legacy UDP discovery', () async {
    messenger.setMockMethodCallHandler(channel, null);
    final value = LanRoomDiscovery(port: 0, nativeDiscoveryEnabled: true);
    addTearDown(() async {
      await value.stop();
      value.dispose();
    });
    expect(await value.startListening(), isTrue);
    expect(value.isListening, isTrue);
  });

  test(
    'a late native start cannot stop a newer scan or admit stale rooms',
    () async {
      final first = Completer<bool>();
      final entered = Completer<void>();
      var starts = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'start') {
          starts++;
          if (starts == 1) {
            entered.complete();
            return first.future;
          }
          return true;
        }
        return null;
      });
      final value = discovery();
      final oldStart = value.startListening();
      await entered.future;
      final oldId = calls.last.arguments['id'] as String;
      expect(await value.startListening(), isTrue);
      final newId = calls.last.arguments['id'] as String;
      expect(newId, isNot(oldId));
      first.complete(true);
      expect(await oldStart, isFalse);
      final stopped = calls.where((call) => call.method == 'stop');
      expect(stopped.map((call) => call.arguments['id']), contains(oldId));
      expect(
        stopped.map((call) => call.arguments['id']),
        isNot(contains(newId)),
      );
      await emit(room(oldId));
      expect(value.currentRooms, isEmpty);
      await emit(room(newId));
      expect(value.currentRooms, hasLength(1));
      expect(value.isListening, isTrue);
    },
  );
}
