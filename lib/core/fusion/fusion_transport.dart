import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../internet/internet_models.dart';
import '../diagnostics/app_log.dart';
import '../internet/hybrid_wifi_link.dart';
import '../security/room_invite.dart';
import '../transport/wifi_direct_manager.dart';
import '../transport/wifi_direct_credentials.dart';
import '../protocol/frame.dart';
import '../protocol/frame_type.dart';
import '../session/room_session.dart';
import '../transport/lan_discovery.dart';
import '../transport/room_transport.dart';
import 'fusion_identity.dart';
import 'fusion_server_api.dart';

/// Deduplicate the *same encrypted packet*, not a sender's wrapping uint16
/// sequence. This also stops loops when several phones bridge the same LAN.
class FusionPacketCache {
  final _seen = <String, DateTime>{};
  bool accept(List<int> packet, DateTime now) {
    while (_seen.isNotEmpty &&
        (now.difference(_seen.values.first).inSeconds >= 15 ||
            _seen.length >= 8192)) {
      _seen.remove(_seen.keys.first);
    }
    final key = sha256.convert(packet).toString();
    if (_seen.containsKey(key)) return false;
    _seen[key] = now;
    return true;
  }
}

class FusionTransport extends RoomTransport implements FusionControlTransport {
  FusionTransport({
    required this.roomId,
    required this.roomName,
    this.identity,
    this.profile,
    this.localPort = defaultPort,
    this.advertise = true,
  });

  static const defaultPort = 8991;
  static const discoveryPort = 8992;
  static const discoveryMagic = 'DAWN_MESH_FUSION_V1';
  final String roomId;
  final String roomName;
  FusionIdentity? identity;
  final ServerProfile? profile;
  final int localPort;
  final bool advertise;
  final status = ValueNotifier<String>('本地融合 · 等待连接');
  RoomSession? _session;
  HttpServer? _server;
  final _local = <WebSocket>{};
  final _nodeId = base64UrlEncode(
    List<int>.generate(16, (_) => Random.secure().nextInt(256)),
  );
  WebSocket? _cloud;
  final _incoming = StreamController<Frame>.broadcast();
  final _cache = FusionPacketCache();
  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 4);
  LanRoomDiscovery? _discovery;
  Timer? _timer;
  bool _stopped = false;
  bool _ending = false;
  bool _ticking = false;
  bool _cloudAuthenticated = false;
  String? _localTarget;
  Uint8List? _state;
  int _revision = 0;
  int _uploadedRevision = 0;
  Future<void>? _stopTask;
  Future<void> Function()? onStop;
  String? _cloudError;
  Future<bool>? _connectingCloud;
  @visibleForTesting
  String? lastConnectionError;
  HybridWifiLink? _wifi;
  final _ownAddresses = <String>{};
  final _connectedTargets = <String, WebSocket>{};
  final _socketNodes = <WebSocket, String>{};
  final _peerRoutes = <int, _FusionPeerRoute>{};
  Future<void>? _peerConnectTask;
  final _dialing = <String>{};
  bool _advertisingDirect = false;
  Future<bool>? _advertisingTask;

  @override
  Stream<Frame> get incoming => _incoming.stream;
  @override
  int get peerCount => _local.length + (_cloud == null ? 0 : 1);
  int get boundPort => _server?.port ?? localPort;
  bool get cloudConnected => _cloud != null && _cloudAuthenticated;
  Uint8List? get signedState => _state;

  static Uri endpoint(ServerProfile profile, String suffix) =>
      FusionServerApi.endpoint(profile, suffix);

  Future<void> start(RoomSession session) async {
    _session = session;
    _server = await HttpServer.bind(InternetAddress.anyIPv4, localPort);
    _server!.listen(_acceptLocal, onError: (Object _) {});
    try {
      for (final network in await NetworkInterface.list()) {
        _ownAddresses.addAll(network.addresses.map((a) => a.address));
      }
    } catch (_) {
      /* Nearby discovery can still work without interface enumeration. */
    }
    if (advertise) {
      _discovery = LanRoomDiscovery(
        port: discoveryPort,
        magic: discoveryMagic,
        includeOwnRoom: true,
      );
      if (await _discovery!.startListening()) {
        _discovery!.startAdvertising(
          roomId: roomId,
          roomName: roomName,
          hostNickname: session.selfNickname,
          tcpPort: boundPort,
          getMemberCount: () =>
              session.state == RoomState.inRoom ? session.members.length : 0,
        );
      }
    }
    _timer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_tick()),
    );
    _updateStatus();
  }

  Future<void> _acceptLocal(HttpRequest request) async {
    if (_stopped) {
      await request.response.close();
      return;
    }
    if (request.uri.path == '/fusion' &&
        request.method == 'GET' &&
        !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'id': roomId, 'name': roomName}));
      await request.response.close();
      return;
    }
    if (request.headers.value('X-Fusion-Node') == _nodeId ||
        request.uri.path != '/fusion/$roomId' ||
        _local.length >= 12 ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    try {
      final socket = await WebSocketTransformer.upgrade(
        request,
        compression: CompressionOptions.compressionOff,
      );
      if (_stopped) {
        await socket.close();
        return;
      }
      _attach(
        socket,
        cloud: false,
        nodeId: request.headers.value('X-Fusion-Node'),
      );
    } catch (_) {
      /* A failed local handshake must not end the room. */
    }
  }

  Future<bool> connectLocal(String host, {int port = defaultPort}) async {
    final previous = _localTarget;
    final target = 'ws://$host:$port/fusion/$roomId';
    _localTarget = target;
    final connected = await _dialLocal(target);
    if (!connected && _localTarget == target) _localTarget = previous;
    return connected;
  }

  Future<bool> _connectLocalTarget() async {
    final target = _localTarget;
    if (target == null || _stopped) return false;
    return _dialLocal(target);
  }

  Future<bool> _dialLocal(String target, {String? nodeId}) async {
    if (_stopped) return false;
    if (nodeId != null &&
        _socketNodes.entries.any(
          (entry) =>
              entry.value == nodeId && entry.key.readyState == WebSocket.open,
        )) {
      return true;
    }
    if (_connectedTargets.containsKey(target)) return true;
    if (!_dialing.add(target)) return false;
    try {
      final socket = await WebSocket.connect(
        target,
        headers: {'X-Fusion-Node': _nodeId},
        compression: CompressionOptions.compressionOff,
      ).timeout(const Duration(seconds: 4));
      if (_stopped) {
        await socket.close();
        return false;
      }
      _attach(socket, cloud: false, nodeId: nodeId);
      _connectedTargets[target] = socket;
      return true;
    } catch (_) {
      return false;
    } finally {
      _dialing.remove(target);
    }
  }

  /// Use the already encrypted room channel for automatic Wi-Fi negotiation.
  /// Only the creator forms a group; cloud entrants join it without toggles.
  void enableWifi(RoomInvite invite) {
    if (_wifi != null || _stopped) return;
    final session = _session!;
    final manager = WifiDirectManager.instance;
    _wifi = HybridWifiLink(
      selfId: '${session.selfMemberId}',
      hostId: '1',
      credentials: WifiDirectCredentials.fromInvite(invite),
      signal: (data) => session.sendFusionControl(
        Uint8List.fromList([3, ...utf8.encode(jsonEncode(data))]),
      ),
      info: manager.getConnectionInfo,
      create: manager.createGroup,
      join: manager.connectKnownGroup,
      disconnect: manager.removeGroup,
      availability: manager.hybridAvailability,
      changed: _updateStatus,
    );
    _wifi!.start();
  }

  /// A remote entrant starts PAKE through the relay. A local entrant never
  /// needs this call (or a server profile) to join.
  Future<bool> connectCloud() {
    final pending = _connectingCloud;
    if (pending != null) return pending;
    late final Future<bool> task;
    task = _connectCloud().whenComplete(() {
      if (identical(_connectingCloud, task)) _connectingCloud = null;
    });
    _connectingCloud = task;
    return task;
  }

  Future<bool> _connectCloud() async {
    if (_cloud != null) return true;
    final server = profile;
    if (server == null || _stopped) return false;
    try {
      if (identity != null && _state != null && _stateIsFresh) await _upload();
      final uri = endpoint(server, '/rooms/$roomId/relay');
      final socket = await WebSocket.connect(
        uri.replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws').toString(),
        headers: {
          'Authorization': 'Bearer ${server.accessToken}',
          if (identity != null) 'X-Fusion-Key': identity!.relayToken,
        },
        compression: CompressionOptions.compressionOff,
      ).timeout(const Duration(seconds: 5));
      if (_stopped) {
        await socket.close();
        return false;
      }
      _cloud = socket;
      _cloudAuthenticated = identity != null;
      _cloudError = null;
      _attach(socket, cloud: true);
      return true;
    } catch (error) {
      AppLog.warn('Fusion', 'Cloud connection unavailable: $error');
      lastConnectionError = '$error';
      _cloudError = FusionServerException.describe(error);
      _updateStatus();
      return false;
    }
  }

  void _attach(WebSocket socket, {required bool cloud, String? nodeId}) {
    if (!cloud) _local.add(socket);
    if (!cloud && nodeId != null) _socketNodes[socket] = nodeId;
    socket.pingInterval = const Duration(seconds: 5);
    var window = DateTime.now();
    var count = 0;
    socket.listen(
      (dynamic message) {
        if (_stopped || message is! List<int>) return;
        final now = DateTime.now();
        if (now.difference(window).inSeconds >= 1) {
          window = now;
          count = 0;
        }
        if (message.length > Frame.maxTotalSize || ++count > 400) {
          unawaited(socket.close());
          return;
        }
        final bytes = Uint8List.fromList(message);
        final frame = Frame.decode(bytes);
        if (frame == null ||
            frame.payload.length + Frame.headerSize != bytes.length ||
            !_allowed(frame)) {
          return;
        }
        if (!_cache.accept(bytes, now)) return;
        // One encrypted packet fans out over both routes and is delivered once.
        // Offline phones can be gateways too; only the destination decodes Opus.
        _fanout(bytes, exclude: socket);
        _incoming.add(frame);
      },
      onError: (Object _) {},
      onDone: () {
        _local.remove(socket);
        _socketNodes.remove(socket);
        _connectedTargets.removeWhere((_, value) => identical(value, socket));
        if (identical(_cloud, socket)) {
          _cloud = null;
          _cloudAuthenticated = false;
        }
        _updateStatus();
      },
    );
    _updateStatus();
  }

  bool _allowed(Frame frame) =>
      frame.type == FrameType.sealed ||
      frame.type == FrameType.handshakeHello ||
      frame.type == FrameType.handshakeConfirm;

  void _fanout(Uint8List bytes, {WebSocket? exclude}) {
    for (final socket in [..._local, ?_cloud]) {
      if (!identical(socket, exclude) && socket.readyState == WebSocket.open) {
        socket.add(bytes);
      }
    }
  }

  @override
  void send(Frame frame, {bool realtime = false}) {
    if (_stopped || !_allowed(frame)) return;
    final bytes = frame.encode();
    if (_cache.accept(bytes, DateTime.now())) _fanout(bytes);
  }

  @override
  Future<void> receiveControl(Frame frame) async {
    if (_stopped || frame.payload.isEmpty) return;
    final data = Uint8List.sublistView(frame.payload, 1);
    if (frame.payload[0] == 1 && identity == null) {
      identity = await FusionIdentity.openBootstrap(data, roomId);
      if (identity != null && _cloud != null && !_cloudAuthenticated) {
        _cloud!.add(jsonEncode({'key': identity!.relayToken}));
        _cloudAuthenticated = true;
      }
    } else if (frame.payload[0] == 4 &&
        _session?.hasFusionIdentity == true &&
        _session!.members.any((member) => member.memberId == frame.senderId) &&
        frame.senderId != _session!.selfMemberId) {
      final route = _FusionPeerRoute.decode(data);
      if (route != null && route.nodeId != _nodeId) {
        _peerRoutes[frame.senderId] = route;
        unawaited(_connectPeerRoutes());
      }
    } else if (frame.payload[0] == 3 && frame.senderId == 1) {
      try {
        _wifi?.receive(
          '1',
          jsonDecode(utf8.decode(data)) as Map<String, dynamic>,
        );
      } catch (_) {}
    } else if (frame.payload[0] == 2 &&
        identity != null &&
        await identity!.verifyState(data)) {
      final revision = ByteData.sublistView(data).getUint64(0);
      if (revision > _revision) {
        _revision = revision;
        _state = data;
        if (data[8] == 1) unawaited(_session?.acceptFusionEnd());
      }
    }
    _updateStatus();
  }

  Future<void> _publishState({bool ended = false}) async {
    final session = _session;
    final signer = identity;
    if (session == null || signer == null || !signer.canSign) return;
    _revision = DateTime.now().millisecondsSinceEpoch > _revision
        ? DateTime.now().millisecondsSinceEpoch
        : _revision + 1;
    final state = await signer.signState(
      session.members,
      _revision,
      ended: ended,
    );
    if (_ending && !ended) return;
    _state = state;
    await session.sendFusionControl(
      Uint8List.fromList([1, ...signer.bootstrap]),
    );
    await session.sendFusionControl(Uint8List.fromList([2, ..._state!]));
  }

  Future<void> _tick() async {
    if (_stopped || _ticking || _ending) return;
    _ticking = true;
    try {
      if (_session?.state == RoomState.inRoom) await _publishState();
      if (_session?.hasFusionIdentity == true) {
        await _announcePeerRoutes();
        unawaited(_connectPeerRoutes());
      }
      // Only the creator advertises a joinable P2P group. Other members still
      // advertise their reachable IP endpoints through LAN discovery.
      if (!_stopped &&
          advertise &&
          !_advertisingDirect &&
          _wifi != null &&
          _session?.isHost == true) {
        _advertisingTask = WifiDirectManager.instance.advertiseFusionRoom(
          roomId,
          roomName,
        );
        _advertisingDirect = await _advertisingTask!;
        _advertisingTask = null;
      }
      if (_wifi != null && _local.isEmpty && _session?.isHost == false) {
        final info = await WifiDirectManager.instance.getConnectionInfo();
        if (info.groupFormed &&
            !info.isGroupOwner &&
            info.groupOwnerAddress.isNotEmpty) {
          await connectLocal(info.groupOwnerAddress);
        }
      }
      if (_local.isEmpty && _session?.hasFusionIdentity == true) {
        for (final room in _discovery?.currentRooms ?? <DiscoveredRoom>[]) {
          if (room.roomId == roomId &&
              room.memberCount > 0 &&
              !_ownAddresses.contains(room.hostAddress.address)) {
            await connectLocal(room.hostAddress.address, port: room.port);
          }
        }
      }
      if (_local.isEmpty && _localTarget != null) await _connectLocalTarget();
      if (identity != null && _state != null && profile != null) {
        if (_cloud == null) {
          await connectCloud();
        } else if (_uploadedRevision < _revision && _stateIsFresh) {
          await _upload();
        }
      }
    } catch (error) {
      _cloudError = FusionServerException.describe(error);
      AppLog.warn('Fusion', 'Room synchronization failed: $error');
    } finally {
      _ticking = false;
      _updateStatus();
    }
  }

  /// Publish a newly created room immediately, then keep it fresh periodically.
  Future<void> synchronize() => _tick();

  bool get _stateIsFresh =>
      _state != null &&
      DateTime.now().millisecondsSinceEpoch -
              ByteData.sublistView(_state!).getUint64(0) <
          85000;

  Future<void> _announcePeerRoutes() async {
    try {
      final networks = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      _ownAddresses.clear();
      for (final network in networks) {
        _ownAddresses.addAll(
          network.addresses.map((address) => address.address),
        );
      }
      final addresses = _ownAddresses
          .where(
            (address) =>
                _FusionPeerRoute.isLocalAddress(address) &&
                !InternetAddress(address).isLoopback,
          )
          .take(4)
          .toList();
      if (addresses.isEmpty || _stopped) return;
      await _session!.sendFusionControl(
        Uint8List.fromList([
          4,
          ...utf8.encode(
            jsonEncode({
              'node': _nodeId,
              'port': boundPort,
              'addresses': addresses,
            }),
          ),
        ]),
      );
    } catch (error) {
      AppLog.debug('Fusion', '成员直连地址暂未就绪：$error');
    }
  }

  Future<void> _connectPeerRoutes() {
    if (_peerConnectTask != null) return _peerConnectTask!;
    late final Future<void> task;
    task = _dialPeerRoutes().whenComplete(() {
      if (identical(_peerConnectTask, task)) _peerConnectTask = null;
    });
    _peerConnectTask = task;
    return task;
  }

  Future<void> _dialPeerRoutes() async {
    final session = _session;
    if (_stopped || session?.hasFusionIdentity != true) return;
    final known = session!.members.map((member) => member.memberId).toSet();
    _peerRoutes.removeWhere((id, _) => !known.contains(id));
    // One dialer per pair avoids two parallel sockets for every pair. These
    // addresses travel over the admitted encrypted channel, never a public list.
    final routes = _peerRoutes.entries
        .where((entry) => session.selfMemberId < entry.key)
        .toList();
    await Future.wait(
      routes.map((entry) async {
        for (final address in entry.value.addresses) {
          if (_stopped) return;
          if (await _dialLocal(
            'ws://$address:${entry.value.port}/fusion/$roomId',
            nodeId: entry.value.nodeId,
          )) {
            return;
          }
        }
      }),
    );
  }

  @override
  Future<void> prepareEnd() async {
    if (_ending || _stopped || identity?.canSign != true) return;
    _ending = true;
    _timer?.cancel();
    await _publishState(ended: true);
  }

  Future<void> _upload() async {
    final server = profile;
    final room = identity;
    final state = _state;
    if (server == null || room == null || state == null) return;
    final request = await _http
        .putUrl(endpoint(server, '/rooms/$roomId'))
        .timeout(const Duration(seconds: 4));
    request.followRedirects = false;
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${server.accessToken}',
    );
    request.headers.set('X-Fusion-Key', room.relayToken);
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'manifest': base64Encode(room.manifest),
        'state': base64Encode(state),
      }),
    );
    final response = await request.close().timeout(const Duration(seconds: 4));
    await response.drain<void>().timeout(const Duration(seconds: 4));
    FusionServerException.checkStatus(response.statusCode, uploading: true);
    _uploadedRevision = ByteData.sublistView(state).getUint64(0);
    _cloudError = null;
  }

  void _updateStatus() {
    if (_stopped) return;
    final wifiHint = _local.isEmpty && _wifi != null
        ? ' · ${_wifi!.status}'
        : '';
    status.value =
        '${_session?.fusionHostUnavailable == true && _session?.hasActiveFusionPeer == true ? '房主暂离线，成员间可通话 · ' : ''}'
        '${_local.isEmpty ? '暂无本地队友连接' : '本地连接 ${_local.length}'} · '
        '${cloudConnected ? '已接通公网' : (_cloudError ?? (profile == null ? '未配置公网服务器' : '正在连接融合房服务器'))}$wifiHint';
  }

  Future<bool> reconnect() async {
    if (_stopped) return false;
    // Do not tear down a working local link when only the cloud disappeared.
    await _connectPeerRoutes();
    if (_local.isEmpty) await _connectLocalTarget();
    if (_cloud == null && profile != null) await connectCloud();
    return peerCount > 0;
  }

  @override
  void updateSelfMemberId(int id) {}
  @override
  void updateKnownMemberIds(Set<int> ids) {}
  @override
  bool get supportsHostTransfer => false;
  @override
  Map<int, String> get peerEndpoints => const {};
  @override
  Future<bool> becomeHost() async => false;
  @override
  Future<bool> reconnectToHost(String endpoint) async => false;
  @override
  Future<void> flush() async {}
  @override
  Future<void> stop() => _stopTask ??= _stop();

  Future<void> _stop() async {
    if (_stopped) return;
    _timer?.cancel();
    await prepareEnd();
    if (_state != null && _state![8] == 1) {
      try {
        await _upload().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    _stopped = true;
    await _advertisingTask;
    if (_advertisingDirect) {
      await WifiDirectManager.instance.stopAdvertisingFusionRoom();
      _advertisingDirect = false;
    }
    _discovery?.dispose();
    await _server?.close(force: true);
    _http.close(force: true);
    for (final socket in [..._local, ?_cloud]) {
      unawaited(socket.close());
    }
    _local.clear();
    _socketNodes.clear();
    _peerRoutes.clear();
    _cloud = null;
    await _wifi?.close();
    await onStop?.call();
  }

  @override
  Future<void> dispose() async {
    await stop();
    if (!_incoming.isClosed) await _incoming.close();
    status.dispose();
  }
}

class _FusionPeerRoute {
  _FusionPeerRoute(this.nodeId, this.port, this.addresses);
  final String nodeId;
  final int port;
  final List<String> addresses;

  static bool isLocalAddress(String value) {
    final address = InternetAddress.tryParse(value);
    if (address?.type != InternetAddressType.IPv4) return false;
    final bytes = address!.rawAddress;
    return address.isLoopback ||
        bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168) ||
        (bytes[0] == 169 && bytes[1] == 254);
  }

  static _FusionPeerRoute? decode(List<int> bytes) {
    try {
      final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final node = data['node'],
          port = data['port'],
          addresses = data['addresses'];
      if (node is! String ||
          node.length != 24 ||
          port is! int ||
          port < 1 ||
          port > 65535 ||
          addresses is! List) {
        return null;
      }
      final valid = addresses
          .whereType<String>()
          .where(isLocalAddress)
          .take(4)
          .toSet()
          .toList();
      return valid.isEmpty ? null : _FusionPeerRoute(node, port, valid);
    } catch (_) {
      return null;
    }
  }
}
