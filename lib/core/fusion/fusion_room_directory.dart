import '../transport/lan_discovery.dart';
import '../transport/wifi_direct_manager.dart';
import 'fusion_server_api.dart';

/// One identity, possibly several reachable entry points. Names are not IDs.
class FusionRoomEntry {
  FusionRoomEntry(this.id, this.name);
  final String id;
  String name;
  int memberCount = 0;
  bool cloud = false;
  final local = <DiscoveredRoom>[];
  final direct = <WifiP2pPeer>[];

  String get sources => [
    if (local.isNotEmpty) '同网连接',
    if (direct.isNotEmpty) 'Wi-Fi 直连',
    if (cloud) '公网',
  ].join(' / ');

  static List<FusionRoomEntry> merge({
    required List<DiscoveredRoom> local,
    required List<WifiP2pPeer> direct,
    required List<Map<String, dynamic>> remote,
  }) {
    final rooms = <String, FusionRoomEntry>{};
    FusionRoomEntry entry(String id, String name, int count) {
      final room = rooms.putIfAbsent(id, () => FusionRoomEntry(id, name));
      if (count > room.memberCount) room.memberCount = count;
      return room;
    }

    for (final source in remote) {
      if (!validFusionRoomId(source['id'])) continue;
      entry(
        source['id'] as String,
        source['name'] as String? ?? '融合房',
        (source['members'] as List?)?.length ?? 0,
      ).cloud = true;
    }
    for (final source in local) {
      if (!validFusionRoomId(source.roomId) || source.memberCount < 1) continue;
      final room = entry(source.roomId, source.roomName, source.memberCount);
      if (!room.local.any(
        (r) => r.hostAddress == source.hostAddress && r.port == source.port,
      )) {
        room.local.add(source);
      }
    }
    for (final source in direct) {
      if (!validFusionRoomId(source.fusionRoomId)) continue;
      final room = entry(
        source.fusionRoomId!,
        source.fusionRoomName ?? '融合房',
        0,
      );
      if (!room.direct.any((p) => p.address == source.address)) {
        room.direct.add(source);
      }
    }
    return rooms.values.toList()..sort((a, b) {
      final nearby =
          (b.local.isNotEmpty || b.direct.isNotEmpty ? 1 : 0) -
          (a.local.isNotEmpty || a.direct.isNotEmpty ? 1 : 0);
      return nearby != 0 ? nearby : a.id.compareTo(b.id);
    });
  }
}
