import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dawn_mesh/core/transport/lan_discovery.dart';

import 'lan_transport_whitelist_test.dart' show pumpUntil;

void main() {
  group('LanRoomDiscovery Tests', () {
    test(
      'asynchronous broadcast errors leave discovery and room reception usable',
      () async {
        final socket = _UnroutableDatagramSocket();
        final discovery = LanRoomDiscovery(
          port: 8992,
          bindSocket: (_) async => socket,
        );
        addTearDown(discovery.dispose);
        expect(await discovery.startListening(), isTrue);
        discovery.startAdvertising(
          roomId: 'local',
          roomName: '本地融合房',
          hostNickname: '房主',
          tcpPort: 8991,
          getMemberCount: () => 1,
        );
        await pumpUntil(
          () => socket.failedSends > 0,
          reason: 'OS should report the failed broadcast asynchronously',
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(discovery.isListening, isTrue);
        final room = discovery.roomsStream.firstWhere(
          (rooms) => rooms.isNotEmpty,
        );
        socket.receiveRoom();
        expect(
          (await room.timeout(const Duration(seconds: 1))).single.roomName,
          '网络恢复后的房间',
        );
        discovery.stopAdvertising(sendGoodbye: false);
      },
    );

    test('初始状态房间列表为空且生命周期释放正常', () async {
      final discovery = LanRoomDiscovery();
      expect(discovery.currentRooms.isEmpty, isTrue);
      expect(discovery.isListening, isFalse);

      await discovery.startListening();
      expect(discovery.isListening, isTrue);

      discovery.stopAdvertising();
      await discovery.stop();
      expect(discovery.isListening, isFalse);
      discovery.dispose();
    });

    test('ROOM_CLOSED 同源包即时移除房间；畸形字段被钳制', () async {
      final discovery = LanRoomDiscovery();
      await discovery.startListening();
      addTearDown(discovery.dispose);

      final advertiser = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(advertiser.close);

      void advertise({required int port, String? name, String? action}) {
        advertiser.send(
          utf8.encode(
            jsonEncode({
              'magic': LanRoomDiscovery.magicHeader,
              'roomId': 'room_origin_test',
              'roomName': name ?? '测试房',
              'hostNickname': '主持人',
              'port': port,
              'members': 2,
              'action': ?action,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            }),
          ),
          InternetAddress.loopbackIPv4,
          LanRoomDiscovery.discoveryPort,
        );
      }

      // 正常广告进入列表
      advertise(port: 8988);
      await pumpUntil(
        () => discovery.currentRooms.any((r) => r.roomId == 'room_origin_test'),
        reason: '正常广播必须被发现',
      );

      // 畸形端口：忽略该包，已有记录不受影响
      advertise(port: 70000);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        discovery.currentRooms
            .firstWhere((r) => r.roomId == 'room_origin_test')
            .port,
        8988,
      );

      // 超长房名：截断到展示上限
      advertise(port: 8988, name: '长' * 500);
      await pumpUntil(
        () =>
            discovery.currentRooms
                .firstWhere((r) => r.roomId == 'room_origin_test')
                .roomName
                .length <=
            LanRoomDiscovery.maxAdvertisedTextLength,
        reason: '广播里的房名不受任何校验，必须钳制长度',
      );

      // 同源解散通知：立即移除
      advertise(port: 8988, action: 'ROOM_CLOSED');
      await pumpUntil(
        () =>
            discovery.currentRooms.every((r) => r.roomId != 'room_origin_test'),
        reason: '同源的 ROOM_CLOSED 必须即时移除房间',
      );
    });

    test('发现列表容量有上限，伪造洪水灌不满内存', () async {
      final discovery = LanRoomDiscovery();
      await discovery.startListening();
      addTearDown(discovery.dispose);

      final advertiser = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(advertiser.close);

      for (int i = 0; i < LanRoomDiscovery.maxDiscoveredRooms + 20; i++) {
        advertiser.send(
          utf8.encode(
            jsonEncode({
              'magic': LanRoomDiscovery.magicHeader,
              'roomId': 'room_flood_$i',
              'roomName': '洪水房$i',
              'hostNickname': '伪造者',
              'port': 8988,
              'members': 1,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            }),
          ),
          InternetAddress.loopbackIPv4,
          LanRoomDiscovery.discoveryPort,
        );
      }

      // 给UDP 处理留一点时间，然后断言列表从未超过上限。
      await pumpUntil(
        () => discovery.currentRooms.length >= 4,
        reason: '至少应收到一部分广播',
        timeout: const Duration(seconds: 3),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(
        discovery.currentRooms.length,
        lessThanOrEqualTo(LanRoomDiscovery.maxDiscoveredRooms),
        reason: '匿名广播可以伪造大量 roomId，列表必须有硬上限',
      );
    });
  });
}

// RawDatagramSocket.send reports local send failures through its stream, after
// returning the byte count. A synchronous try/catch around send cannot catch it.
class _UnroutableDatagramSocket extends Stream<RawSocketEvent>
    implements RawDatagramSocket {
  final events = StreamController<RawSocketEvent>();
  final packets = <Datagram>[];
  int failedSends = 0;
  @override
  bool broadcastEnabled = false;

  @override
  StreamSubscription<RawSocketEvent> listen(
    void Function(RawSocketEvent)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => events.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  int send(List<int> bytes, InternetAddress address, int port) {
    scheduleMicrotask(() {
      if (events.isClosed) return;
      failedSends++;
      events.addError(
        SocketException(
          'Send failed',
          osError: const OSError('No route to host', 65),
          address: address,
          port: port,
        ),
      );
    });
    return bytes.length;
  }

  void receiveRoom() {
    packets.add(
      Datagram(
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'magic': LanRoomDiscovery.magicHeader,
              'roomId': 'remote',
              'roomName': '网络恢复后的房间',
              'hostNickname': '另一位房主',
              'port': 8991,
              'members': 1,
            }),
          ),
        ),
        InternetAddress.loopbackIPv4,
        8992,
      ),
    );
    events.add(RawSocketEvent.read);
  }

  @override
  Datagram? receive() => packets.isEmpty ? null : packets.removeAt(0);
  @override
  void close() {
    unawaited(events.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
