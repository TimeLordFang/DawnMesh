import 'dart:io';

import 'package:dawn_mesh/core/fusion/fusion_room_directory.dart';
import 'package:dawn_mesh/core/transport/lan_discovery.dart';
import 'package:dawn_mesh/core/transport/wifi_direct_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final id = 'a' * 43;
  DiscoveredRoom local(String host) => DiscoveredRoom(
    roomId: id,
    roomName: '队伍',
    hostNickname: '房主',
    hostAddress: InternetAddress(host),
    port: 8991,
    memberCount: 2,
    lastSeen: DateTime.now(),
  );
  test('public, LAN gateways and Wi-Fi Direct collapse by room ID, retaining routes', () {
    final rooms = FusionRoomEntry.merge(
      local: [local('192.168.1.2'), local('192.168.1.3'), local('192.168.1.2')],
      direct: [
        WifiP2pPeer.fromMap({
          'name': '手机',
          'address': 'aa:bb:cc:dd:ee:ff',
          'fusionRoomId': id,
          'fusionRoomName': '队伍',
        }),
      ],
      remote: [
        {
          'id': id,
          'name': '队伍',
          'members': [{}, {}, {}],
        },
      ],
    );
    expect(rooms, hasLength(1));
    expect(rooms.single.local, hasLength(2));
    expect(rooms.single.direct, hasLength(1));
    expect(rooms.single.cloud, isTrue);
    expect(
      rooms.single.memberCount,
      3,
    ); // Count once, never add gateway counts.
    expect(rooms.single.sources, '同网连接 / Wi-Fi 直连 / 公网');
    final offline = FusionRoomEntry.merge(
      local: [local('192.168.1.2')],
      direct: [],
      remote: [],
    );
    expect(offline.single.id, id);
    expect(offline.single.cloud, isFalse);
  });
  test(
    'identical names and unidentified legacy devices are never merged by guess',
    () {
      final rooms = FusionRoomEntry.merge(
        local: [],
        direct: [
          WifiP2pPeer.fromMap({'name': '队伍'}),
        ],
        remote: [
          {'id': id, 'name': '队伍'},
          {'id': 'b' * 43, 'name': '队伍'},
          {'id': 'invalid'},
        ],
      );
      expect(rooms, hasLength(2));
      expect(rooms.every((r) => r.direct.isEmpty), isTrue);
    },
  );
}
