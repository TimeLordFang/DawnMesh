import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/audio/audio_io.dart';
import '../../core/fusion/fusion_identity.dart';
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
  String? _cloudStatus;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_discovery.startListening());
    _peerSubscription = WifiDirectManager.instance.peersStream.listen((peers) {
      if (mounted) setState(() => _peers = peers);
    });
    unawaited(WifiDirectManager.instance.discoverPeers());
    unawaited(_loadProfiles());
    _refresh = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_busy) unawaited(_loadRemote());
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
      final request = await _http
          .getUrl(FusionTransport.endpoint(profile, '/rooms'))
          .timeout(const Duration(seconds: 4));
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${profile.accessToken}',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 4),
      );
      if (response.statusCode != 200) {
        throw HttpException('${response.statusCode}');
      }
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 4));
      final json = jsonDecode(text) as Map<String, dynamic>;
      if (json['protocolVersion'] != 1) throw const FormatException();
      final rooms = (json['rooms'] as List)
          .whereType<Map<String, dynamic>>()
          .where(
            (r) =>
                r['id'] is String &&
                RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(r['id'] as String),
          )
          .take(256)
          .toList();
      if (mounted && identical(profile, _profile)) {
        setState(() {
          _remoteRooms = rooms;
          _cloudStatus = '已连接服务器 · 附近成员可代为同步';
        });
      }
    } catch (_) {
      if (mounted && identical(profile, _profile)) {
        setState(() {
          _remoteRooms = [];
          _cloudStatus = '公网暂不可用或服务器尚未支持融合房，仍可在附近建房、加入';
        });
      }
    } finally {
      _loadingRemote = false;
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

  Future<void> _join({
    String? id,
    String? name,
    String? host,
    int port = FusionTransport.defaultPort,
    WifiP2pPeer? peer,
    bool cloud = false,
  }) async {
    if (_busy) return;
    final invite = await requestRoomInvite(context);
    if (invite == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    RoomSession? session;
    bool ownsGroup = false;
    try {
      if (peer != null) {
        final info = await WifiDirectManager.instance.connectAndWait(
          peer.address,
          credentials: WifiDirectCredentials.fromInvite(invite),
        );
        if (info == null ||
            !info.isConnected ||
            info.groupOwnerAddress.isEmpty) {
          throw const SocketException('Wi-Fi Direct unavailable');
        }
        ownsGroup = true;
        host = info.groupOwnerAddress;
        final request = await _http
            .getUrl(Uri.http('$host:$port', '/fusion'))
            .timeout(const Duration(seconds: 4));
        final response = await request.close().timeout(
          const Duration(seconds: 4),
        );
        final data = jsonDecode(
          await response
              .transform(utf8.decoder)
              .join()
              .timeout(const Duration(seconds: 4)),
        ) as Map<String, dynamic>;
        id = data['id'] as String;
        name = data['name'] as String;
      }
      if (id == null || !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(id)) {
        throw const FormatException();
      }
      session = await _newSession(id, invite);
      final transport = FusionTransport(
        roomId: id,
        roomName: name ?? '融合房',
        profile: _profile,
      );
      if (ownsGroup) transport.onStop = WifiDirectManager.instance.removeGroup;
      session.attachTransport(transport, reconnect: transport.reconnect);
      await transport.start(session);
      final connected = cloud
          ? await transport.connectCloud()
          : await transport.connectLocal(host!, port: port);
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
                    unawaited(WifiDirectManager.instance.discoverPeers());
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
            label: const Text('创建融合房 · 最多 6 人'),
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
          Text('附近房间', style: Theme.of(context).textTheme.titleMedium),
          StreamBuilder<List<DiscoveredRoom>>(
            stream: _discovery.roomsStream,
            initialData: _discovery.currentRooms,
            builder: (_, snapshot) {
              final rooms = snapshot.data ?? [];
              return Column(
                children: [
                  for (final room in rooms)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.wifi_rounded),
                      title: Text(room.roomName),
                      subtitle: Text('${room.memberCount} 人 · 本地连接'),
                      onTap: _busy
                          ? null
                          : () => _join(
                              id: room.roomId,
                              name: room.roomName,
                              host: room.hostAddress.address,
                              port: room.port,
                            ),
                    ),
                  if (rooms.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '同一 Wi-Fi 或热点下的融合房会显示在这里。也可在下方选择附近设备建立 Wi-Fi 直连。',
                      ),
                    ),
                ],
              );
            },
          ),
          for (final peer in _peers)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.wifi_tethering_rounded),
              title: Text(peer.name),
              subtitle: const Text('通过 Wi-Fi 直连加入融合房'),
              onTap: _busy ? null : () => _join(peer: peer),
            ),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: Text(
                  '公网桥接（可选）',
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
                });
                unawaited(_store.saveSelectedId(p.id));
                unawaited(_loadRemote());
              },
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(_cloudStatus ?? '未配置服务器也能在附近使用；配置同一服务器的联网成员会自动接通公网。'),
          ),
          for (final room in _remoteRooms)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.public_rounded),
              title: Text(room['name'] as String? ?? '融合房'),
              subtitle: Text(
                '${(room['members'] as List?)?.length ?? 0} 人 · 经联网成员接入',
              ),
              onTap: _busy
                  ? null
                  : () => _join(
                      id: room['id'] as String,
                      name: room['name'] as String?,
                      cloud: true,
                    ),
            ),
        ],
      ),
    ),
  );
}
