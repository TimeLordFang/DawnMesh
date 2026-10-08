import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/audio/audio_io.dart';
import '../../core/fusion/fusion_identity.dart';
import '../../core/protocol/room_limits.dart';
import '../../core/fusion/fusion_room_directory.dart';
import '../../core/fusion/fusion_server_api.dart';
import '../../core/fusion/fusion_transport.dart';
import '../../core/internet/internet_models.dart';
import '../../core/internet/server_profile_store.dart';
import '../../core/security/room_invite.dart';
import '../../core/session/room_session.dart';
import '../../core/transport/lan_discovery.dart';
import '../../core/transport/wifi_direct_credentials.dart';
import '../../core/transport/wifi_direct_manager.dart';
import '../widgets/room_invite_dialog.dart';
import '../widgets/server_profile_picker.dart';
import 'internet_home_page.dart';

class FusionHomePage extends StatefulWidget {
  const FusionHomePage({
    super.key,
    required this.audioIo,
    required this.nickname,
    required this.isNight,
  });
  final AudioIo audioIo;
  final String nickname;
  final bool isNight;
  @override
  State<FusionHomePage> createState() => _FusionHomePageState();
}

class _FusionHomePageState extends State<FusionHomePage> {
  final _store = ServerProfileStore();
  final _discovery = LanRoomDiscovery(
    port: FusionTransport.discoveryPort,
    magic: FusionTransport.discoveryMagic,
    includeOwnRoom: true,
  );
  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 4);
  List<ServerProfile> _profiles = [];
  ServerProfile? _profile;
  List<Map<String, dynamic>> _remoteRooms = [];
  List<WifiP2pPeer> _peers = [];
  StreamSubscription<List<WifiP2pPeer>>? _peerSubscription;
  Timer? _refresh;
  bool _busy = false;
  bool _loadingRemote = false;
  bool _scanningNearby = false;
  String? _cloudStatus;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_discovery.startListening());
    _peerSubscription = WifiDirectManager.instance.peersStream.listen((peers) {
      if (mounted) setState(() => _peers = peers);
    });
    unawaited(_scanNearby());
    unawaited(_loadProfiles());
    _refresh = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_busy) {
        unawaited(_loadRemote());
        unawaited(_scanNearby());
      }
    });
  }

  Future<void> _loadProfiles() async {
    final profiles = await _store.loadProfiles();
    final id = await _store.loadSelectedId();
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _profile =
          profiles.where((p) => p.id == id).firstOrNull ?? profiles.firstOrNull;
    });
    await _loadRemote();
  }

  Future<void> _loadRemote() async {
    final profile = _profile;
    if (profile == null || _loadingRemote) return;
    _loadingRemote = true;
    try {
      final rooms = await FusionServerApi.rooms(_http, profile);
      if (mounted && identical(profile, _profile)) {
        setState(() {
          _remoteRooms = rooms;
          _cloudStatus = '已连接服务器 · 附近成员可代为同步';
        });
      }
    } catch (error) {
      if (mounted && identical(profile, _profile)) {
        setState(() {
          _remoteRooms = [];
          _cloudStatus = FusionServerException.describe(error);
        });
      }
    } finally {
      _loadingRemote = false;
      if (mounted && !identical(profile, _profile)) unawaited(_loadRemote());
    }
  }

  Future<void> _scanNearby() async {
    if (!mounted || _busy || _scanningNearby) return;
    _scanningNearby = true;
    final manager = WifiDirectManager.instance;
    try {
      if (!await manager.discoverFusionRooms() && mounted && !_busy) {
        await manager.discoverPeers();
      }
    } finally {
      _scanningNearby = false;
    }
  }

  Future<void> _addServer() async {
    final result = await showDialog<ServerProfile>(
      context: context,
      builder: (_) => const ServerProfileDialog(),
    );
    if (result == null) return;
    await _store.saveProfiles([..._profiles, result]);
    await _store.saveSelectedId(result.id);
    await _loadProfiles();
  }

  Future<void> _create() async {
    final invite = await requestRoomInvite(context, creating: true);
    if (invite == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    RoomSession? session;
    FusionTransport? transport;
    try {
      await WifiDirectManager.instance.stopFusionDiscovery();
      final identity = await FusionIdentity.create('${widget.nickname}的融合房');
      session = await _newSession(identity.roomId, invite);
      transport = FusionTransport(
        roomId: identity.roomId,
        roomName: identity.name,
        identity: identity,
        profile: _profile,
      );
      session.attachTransport(transport, reconnect: transport.reconnect);
      await transport.start(session);
      await session.createRoom(startAudio: false);
      unawaited(transport.synchronize());
      // Local LAN/hotspot works even on phones without Wi-Fi Direct support.
      final manager = WifiDirectManager.instance;
      if (await manager.createGroup(WifiDirectCredentials.fromInvite(invite))) {
        transport.onStop = manager.removeGroup;
      }
      if (!mounted) {
        await session.dispose();
        return;
      }
      transport.enableWifi(invite);
      Navigator.pop(context, (session, identity.name));
    } catch (_) {
      await session?.dispose();
      if (session == null) await transport?.dispose();
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '无法建立本地融合房，请检查 Wi-Fi 和附近设备权限';
        });
      }
    }
  }

  Future<RoomSession> _newSession(String id, RoomInvite invite) async {
    final proof = await _store.deviceProof();
    final session = RoomSession(
      audioIo: widget.audioIo,
      selfNickname: widget.nickname,
      mode: RoomMode.fusion,
      sessionToken: FusionIdentity.memberToken(proof, id),
    );
    await session.protectWithInvite(invite);
    return session;
  }

  Future<void> _join({FusionRoomEntry? room, WifiP2pPeer? peer}) async {
    if (_busy) return;
    final invite = await requestRoomInvite(context);
    if (invite == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    RoomSession? session;
    bool ownsGroup = false;
    String? id = room?.id;
    String? name = room?.name;
    String? directHost;

    Future<String> openDirect(WifiP2pPeer target) async {
      final info = await WifiDirectManager.instance.connectAndWait(
        target.address,
        credentials: WifiDirectCredentials.fromInvite(invite),
      );
      if (info == null || !info.isConnected || info.groupOwnerAddress.isEmpty) {
        throw const SocketException('Wi-Fi Direct unavailable');
      }
      ownsGroup = true;
      final host = info.groupOwnerAddress;
      final request = await _http
          .getUrl(Uri.http('$host:${FusionTransport.defaultPort}', '/fusion'))
          .timeout(const Duration(seconds: 4));
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 4),
      );
      final data = jsonDecode(
        await response
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 4)),
      ) as Map<String, dynamic>;
      final foundId = data['id'];
      if (!validFusionRoomId(foundId) || (id != null && foundId != id)) {
        throw const FormatException('Discovered room changed');
      }
      id = foundId as String;
      name ??= data['name'] as String?;
      return host;
    }

    try {
      await WifiDirectManager.instance.stopFusionDiscovery();
      if (peer != null) directHost = await openDirect(peer);
      if (!validFusionRoomId(id)) throw const FormatException();
      session = await _newSession(id!, invite);
      final transport = FusionTransport(
        roomId: id!,
        roomName: name ?? '融合房',
        profile: _profile,
      );
      transport.onStop = () async {
        if (ownsGroup) await WifiDirectManager.instance.removeGroup();
      };
      session.attachTransport(transport, reconnect: transport.reconnect);
      await transport.start(session);
      var connected = false;
      for (final route in room?.local ?? <DiscoveredRoom>[]) {
        if (await transport.connectLocal(
          route.hostAddress.address,
          port: route.port,
        )) {
          connected = true;
          break;
        }
      }
      // Use an existing route first. Public entrants automatically negotiate
      // nearby Wi-Fi after admission, without another invite dialog.
      if (!connected && room?.cloud == true) {
        connected = await transport.connectCloud();
      }
      if (!connected && directHost != null) {
        connected = await transport.connectLocal(directHost);
      }
      if (!connected) {
        for (final route in room?.direct ?? <WifiP2pPeer>[]) {
          try {
            directHost = await openDirect(route);
            connected = await transport.connectLocal(directHost);
            if (connected) break;
          } catch (_) {
            if (ownsGroup) await WifiDirectManager.instance.removeGroup();
            ownsGroup = false;
          }
        }
      }
      if (!connected) throw const SocketException('No route');
      final joined = session.stateStream
          .firstWhere((s) => s == RoomState.inRoom)
          .timeout(const Duration(seconds: 10));
      await session.joinRoom(startAudio: false);
      await joined;
      if (!mounted) {
        await session.dispose();
        return;
      }
      transport.enableWifi(invite);
      Navigator.pop(context, (session, name ?? '融合房'));
    } catch (_) {
      await session?.dispose();
      if (ownsGroup) await WifiDirectManager.instance.removeGroup();
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '未能加入，请确认四位邀请码和与房主之间的连接';
        });
      }
    }
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _peerSubscription?.cancel();
    unawaited(WifiDirectManager.instance.stopFusionDiscovery());
    _discovery.dispose();
    _http.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('融合房'),
        actions: [
          IconButton(
            tooltip: '刷新附近和公网房间',
            onPressed: _busy
                ? null
                : () {
                    unawaited(_scanNearby());
                    unawaited(_loadRemote());
                  },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '附近直连，联网即汇合',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            '没有移动网络也能建房和加入。连接同一 Wi-Fi、热点或 Wi-Fi 直连后，凭四位码通话。任一成员连上服务器，就能为整组同步成员并连接远程队友。',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('create-fusion-room'),
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.add_rounded),
            label: const Text('创建融合房 · 最多 ${RoomLimits.fusionMembers} 人'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 18),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: Text(
                  '公网服务器（可选）',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: _busy ? null : _addServer,
                child: const Text('添加服务器'),
              ),
            ],
          ),
          if (_profiles.isNotEmpty)
            ServerProfilePicker(
              profiles: _profiles,
              selected: _profile,
              isNight: widget.isNight,
              enabled: !_busy,
              onSelected: (p) {
                setState(() {
                  _profile = p;
                  _remoteRooms = [];
                  _cloudStatus = '正在连接融合房服务器…';
                });
                unawaited(_store.saveSelectedId(p.id));
                unawaited(_loadRemote());
              },
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(_cloudStatus ?? '未配置服务器也能在附近使用；配置同一服务器的联网成员会自动接通公网。'),
          ),
          const Divider(height: 24),
          Text('可加入的融合房', style: Theme.of(context).textTheme.titleMedium),
          StreamBuilder<List<DiscoveredRoom>>(
            stream: _discovery.roomsStream,
            initialData: _discovery.currentRooms,
            builder: (_, snapshot) {
              final rooms = FusionRoomEntry.merge(
                local: snapshot.data ?? [],
                direct: _peers,
                remote: _remoteRooms,
              );
              return Column(
                children: [
                  for (final room in rooms)
                    ListTile(
                      key: ValueKey('fusion-room-${room.id}'),
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        room.local.isNotEmpty || room.direct.isNotEmpty
                            ? Icons.wifi_rounded
                            : Icons.public_rounded,
                      ),
                      title: Text(room.name),
                      subtitle: Text(
                        '${room.memberCount > 0 ? '${room.memberCount} 人 · ' : ''}${room.sources}',
                      ),
                      onTap:
                          _busy || room.memberCount >= RoomLimits.fusionMembers
                          ? null
                          : () => _join(room: room),
                    ),
                  if (rooms.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '暂未发现融合房。联网后显示所选服务器中的房间，也会自动搜索同一 Wi-Fi、热点和附近的直连房间。',
                      ),
                    ),
                ],
              );
            },
          ),
          if (_peers.any((p) => !validFusionRoomId(p.fusionRoomId))) ...[
            const SizedBox(height: 12),
            Text('附近设备（未识别房间）', style: Theme.of(context).textTheme.titleSmall),
            for (final peer in _peers.where(
              (p) => !validFusionRoomId(p.fusionRoomId),
            ))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.wifi_tethering_rounded),
                title: Text(peer.name),
                subtitle: const Text('旧版或未广播房间信息的设备，可尝试直连'),
                onTap: _busy ? null : () => _join(peer: peer),
              ),
          ],
        ],
      ),
    ),
  );
}
