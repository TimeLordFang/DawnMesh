import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../diagnostics/app_log.dart';

const String _tag = '房间发现';

/// 通过局域网 DNS-SD / UDP 或苹果点对点链路发现的房间。
class DiscoveredRoom {
  final String roomId;
  final String roomName;
  final String hostNickname;
  final InternetAddress hostAddress;
  final int port;
  final int memberCount;

  /// Opaque native Bonjour endpoint; retains the Apple peer interface scope.
  final String? applePeerService;
  final DateTime lastSeen;

  DiscoveredRoom({
    required this.roomId,
    required this.roomName,
    required this.hostNickname,
    required this.hostAddress,
    required this.port,
    required this.memberCount,
    required this.lastSeen,
    this.applePeerService,
  });

  @override
  String toString() =>
      'DiscoveredRoom($roomName by $hostNickname at ${hostAddress.address}:$port, $memberCount members)';
}

/// 局域网/热点下的 DNS-SD + UDP 发现；iOS 同时保留苹果点对点端点。
class LanRoomDiscovery {
  LanRoomDiscovery({
    this.port = discoveryPort,
    this.magic = magicHeader,
    this.includeOwnRoom = false,
    this._bindSocket,
    this._nativeDiscoveryEnabled,
  });
  final Future<RawDatagramSocket> Function(bool reusePort)? _bindSocket;
  final bool? _nativeDiscoveryEnabled;
  bool get _usesBonjour =>
      _nativeDiscoveryEnabled ?? (Platform.isIOS || Platform.isAndroid);
  final int port;
  final String magic;
  final bool includeOwnRoom;
  static final _unicastTargets = <InternetAddress>{};
  static void addUnicastTarget(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4 || address.isLoopback) return;
    if (_unicastTargets.length < 16) _unicastTargets.add(address);
  }

  static const int discoveryPort = 8990;
  static const String magicHeader = "DAWN_MESH_DISCOVERY_V1";

  /// 发现列表容量上限。广播匿名可伪造，过期清理 3.5 秒才跑一轮，
  /// 没有上限的话伪造洪水能在窗口内灌出上千个假房间。
  static const int maxDiscoveredRooms = 64;

  /// 房名/昵称展示上限（字符）。广播里的字段不受任何校验，超长文本
  /// 会撑爆房间卡片的单行布局。
  static const int maxAdvertisedTextLength = 64;

  static const _bonjour = MethodChannel('dev.dawnmesh.intercom/bonjour');
  static final _bonjourEvents = const EventChannel(
    'dev.dawnmesh.intercom/bonjour_events',
  ).receiveBroadcastStream();
  String _bonjourId = '';
  StreamSubscription<dynamic>? _bonjourSubscription;
  final _bonjourRooms = <String, Map<String, dynamic>>{};
  Timer? _bonjourRefresh;
  bool _bonjourActive = false;
  RawDatagramSocket? _socket;
  bool _disposed = false;
  int _generation = 0;
  Timer? _broadcastTimer;
  Timer? _pruneTimer;
  final Map<String, DiscoveredRoom> _discoveredRooms = {};

  /// 自己作为房主时广播的房间号——用来把自己从「附近的房间」里滤掉。
  String? _selfRoomId;

  final _roomsController = StreamController<List<DiscoveredRoom>>.broadcast();
  Stream<List<DiscoveredRoom>> get roomsStream => _roomsController.stream;
  List<DiscoveredRoom> get currentRooms => _discoveredRooms.values.toList();

  // 上次发出的列表指纹。广播每秒都会刷新 lastSeen 并重建房间对象，
  // 但 UI 关心的字段往往没变；不去重的话首页列表（含退场转场期间）
  // 会被按秒整棵重建。
  String? _lastRoomsSignature;

  bool get isListening => _socket != null || _bonjourActive;

  /// 开始监听 UDP 8990 上的房间广播。
  Future<bool> startListening() async {
    await stop();
    if (_disposed) return false;
    final generation = _generation;

    // reusePort 在 Windows 上不被支持，会直接抛异常，退回不带该选项重试。
    final socket =
        await _bind(reusePort: true) ?? await _bind(reusePort: false);
    if (_disposed || generation != _generation) {
      socket?.close();
      return false;
    }
    _socket = socket;
    if (_usesBonjour) {
      final bonjourId = _bonjourId =
          '$magic:$port:${identityHashCode(this)}:$generation';
      var started = false;
      _bonjourSubscription = _bonjourEvents.listen((dynamic event) {
        if (_disposed ||
            generation != _generation ||
            event is! Map ||
            event['id'] != bonjourId) {
          return;
        }
        if (event['type'] == 'error') {
          AppLog.warn(_tag, event['message'] as String? ?? 'Bonjour 发现不可用');
          return;
        }
        final service = event['service'];
        if (service is! String) return;
        if (event['type'] == 'removed') {
          final old = _bonjourRooms.remove(service);
          if (old != null) {
            _discoveredRooms.removeWhere(
              (_, known) =>
                  known.roomId == old['roomId'] &&
                  (known.applePeerService == service ||
                      (known.hostAddress.address == old['address'] &&
                          known.port == old['port'])),
            );
            _notifyRoomsChanged();
          }
          return;
        }
        if (event['type'] == 'room' &&
            _validBonjour(event) &&
            (_bonjourRooms.containsKey(service) ||
                _bonjourRooms.length < maxDiscoveredRooms)) {
          _bonjourRooms[service] = Map<String, dynamic>.from(event);
          _acceptBonjour(_bonjourRooms[service]!);
        }
      }, onError: (Object error) => AppLog.warn(_tag, 'Bonjour 发现失败', error));
      try {
        started =
            await _bonjour.invokeMethod<bool>('start', {
              'magic': magic,
              'id': bonjourId,
            }) ??
            false;
      } on MissingPluginException catch (error) {
        AppLog.debug(_tag, '原生同网发现不可用，保留 UDP：$error');
      } on PlatformException catch (error) {
        AppLog.warn(_tag, '本地网络发现权限未就绪，可手动输入房主地址', error);
      }
      if (_disposed || generation != _generation) {
        await _bonjour
            .invokeMethod<void>('stop', {'magic': magic, 'id': bonjourId})
            .catchError((Object _) {});
        return false;
      }
      _bonjourActive = started;
      _bonjourRefresh = Timer.periodic(const Duration(seconds: 1), (_) {
        for (final room in _bonjourRooms.values) {
          _acceptBonjour(room);
        }
      });
    }

    if (_socket == null && !_bonjourActive) {
      AppLog.error(_tag, '无法监听 UDP $discoveryPort，扫描不到附近的房间');
      return false;
    }

    if (_socket != null) _socket!.broadcastEnabled = true;
    var errorReported = false;
    _socket?.listen(
      (event) {
        if (_disposed ||
            generation != _generation ||
            event != RawSocketEvent.read) {
          return;
        }
        final datagram = socket?.receive();
        if (datagram != null) _handleIncomingPacket(datagram);
      },
      onError: (Object error) {
        // UDP send reports local route/permission failures asynchronously through
        // this stream. Keep listening so another interface or recovered network
        // can still discover rooms; the active room transport is independent.
        if (_disposed || generation != _generation || errorReported) return;
        errorReported = true;
        AppLog.warn(_tag, 'UDP 房间发现受限，保持房间并等待网络恢复', error);
      },
      cancelOnError: false,
    );

    AppLog.info(_tag, '已开始监听 UDP $discoveryPort');
    return true;
  }

  Future<RawDatagramSocket?> _bind({required bool reusePort}) async {
    try {
      if (_bindSocket != null) return await _bindSocket(reusePort);
      return await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
        reusePort: reusePort,
      );
    } catch (e) {
      if (reusePort) {
        AppLog.debug(_tag, '带 reusePort 绑定失败，改用兼容方式重试：$e');
      } else {
        AppLog.error(_tag, '绑定 UDP $discoveryPort 失败', e);
      }
      return null;
    }
  }

  /// 作为房主开始广播房间信息。
  void startAdvertising({
    required String roomId,
    required String roomName,
    required String hostNickname,
    required int tcpPort,
    required int Function() getMemberCount,
  }) {
    if (!isListening) {
      AppLog.error(_tag, '发现通道未就绪，房间广播没有发出，其他人搜不到这个房间');
      return;
    }

    _selfRoomId = roomId;
    _broadcastTimer?.cancel();
    if (_usesBonjour) {
      _advertiseBonjour(
        roomId,
        roomName,
        hostNickname,
        tcpPort,
        getMemberCount(),
      );
    }
    _broadcastTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_usesBonjour) {
        _advertiseBonjour(
          roomId,
          roomName,
          hostNickname,
          tcpPort,
          getMemberCount(),
        );
      }
      _sendBroadcast(
        roomId: roomId,
        roomName: roomName,
        hostNickname: hostNickname,
        tcpPort: tcpPort,
        memberCount: getMemberCount(),
      );
    });
    AppLog.info(_tag, '房间「$roomName」开始广播（控制端口 $tcpPort）');
  }

  /// 停止广播；[sendGoodbye] 为 true 时向局域网发送即时解散通知，
  /// 让其他设备列表立刻清除该房间，无需等待超时。
  void stopAdvertising({bool sendGoodbye = true}) {
    if (_usesBonjour && _bonjourActive) {
      unawaited(
        _bonjour
            .invokeMethod<void>('stopAdvertising', {
              'magic': magic,
              'id': _bonjourId,
            })
            .catchError((Object error) {
              AppLog.debug(_tag, '停止 Bonjour 广播：$error');
            }),
      );
    }
    if (sendGoodbye && _selfRoomId != null && _socket != null) {
      final lastRoomId = _selfRoomId!;
      _sendBroadcast(
        roomId: lastRoomId,
        roomName: "",
        hostNickname: "",
        tcpPort: 0,
        memberCount: 0,
        action: "ROOM_CLOSED",
      );
      Future.delayed(const Duration(milliseconds: 80), () {
        if (_socket != null) {
          _sendBroadcast(
            roomId: lastRoomId,
            roomName: "",
            hostNickname: "",
            tcpPort: 0,
            memberCount: 0,
            action: "ROOM_CLOSED",
          );
        }
      });
    }

    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _selfRoomId = null;
  }

  bool _validBonjour(Map<dynamic, dynamic> room) {
    final address = room['address'];
    final tcpPort = room['port'];
    return room['magic'] == magic &&
        room['roomId'] is String &&
        (room['roomId'] as String).isNotEmpty &&
        room['roomName'] is String &&
        room['hostNickname'] is String &&
        address is String &&
        InternetAddress.tryParse(address) != null &&
        tcpPort is int &&
        tcpPort > 0 &&
        tcpPort <= 65535 &&
        (room['members'] == null || room['members'] is int) &&
        (room['peerService'] == null || room['peerService'] is String);
  }

  void _acceptBonjour(Map<String, dynamic> room) {
    final address = InternetAddress.tryParse(room['address'] as String? ?? '');
    if (address == null) return;
    _handleIncomingPacket(
      Datagram(utf8.encode(jsonEncode(room)), address, port),
      applePeerService: room["peerService"] as String?,
    );
  }

  void _advertiseBonjour(
    String id,
    String name,
    String nickname,
    int tcpPort,
    int members,
  ) {
    unawaited(
      _bonjour
          .invokeMethod<void>('advertise', {
            'id': _bonjourId,
            'magic': magic,
            'roomId': id,
            'roomName': name,
            'hostNickname': nickname,
            'port': tcpPort,
            'members': members,
          })
          .catchError((Object error) {
            AppLog.warn(_tag, 'Bonjour 广播失败', error);
          }),
    );
  }

  Future<List<InternetAddress>> _getBroadcastAddresses() async {
    final addresses = <InternetAddress>{
      ..._unicastTargets,
      InternetAddress("255.255.255.255"),
    };

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            // 计算热点/局域网 /24 定向子网广播（如 192.168.43.255）
            final directed = '${parts[0]}.${parts[1]}.${parts[2]}.255';
            addresses.add(InternetAddress(directed));
          }
        }
      }
    } catch (e) {
      AppLog.debug(_tag, '获取本地网卡广播地址失败: $e');
    }

    return addresses.toList();
  }

  void _sendBroadcast({
    required String roomId,
    required String roomName,
    required String hostNickname,
    required int tcpPort,
    required int memberCount,
    String? action,
  }) async {
    final socket = _socket;
    if (socket == null) return;

    final jsonPayload = jsonEncode({
      "magic": magic,
      "roomId": roomId,
      "roomName": roomName,
      "hostNickname": hostNickname,
      "port": tcpPort,
      "members": memberCount,
      "action": ?action,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    });

    final bytes = utf8.encode(jsonPayload);
    final targets = await _getBroadcastAddresses();
    for (final target in targets) {
      try {
        socket.send(bytes, target, port);
      } catch (_) {
        // 部分接口若不支持广播，静默跳过
      }
    }
  }

  void _handleIncomingPacket(Datagram datagram, {String? applePeerService}) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
    } catch (e) {
      // 同网段其他应用的广播包，属于正常噪声，不打扰用户。
      AppLog.debug(_tag, '忽略无法解析的广播包（${datagram.data.length} 字节）');
      return;
    }

    if (json["magic"] != magic) return;

    try {
      final roomId = json["roomId"] as String;

      // 广播是发到 255.255.255.255 的，自己也会收到自己的包。
      if (!includeOwnRoom && roomId == _selfRoomId) return;

      // 收到解散通知，即刻移除。广播谁都能发，只有与该房间最后一次
      // 广播同源的解散包才算数——否则任何设备都能把别人列表里的
      // 房间踢掉。
      if (json["action"] == "ROOM_CLOSED") {
        if (includeOwnRoom) {
          _discoveredRooms.removeWhere(
            (_, known) =>
                known.roomId == roomId &&
                known.hostAddress.address == datagram.address.address,
          );
          _notifyRoomsChanged();
          return;
        }
        final known = _discoveredRooms[roomId];
        if (known != null &&
            known.hostAddress.address == datagram.address.address) {
          _discoveredRooms.remove(roomId);
          AppLog.info(_tag, '收到房间 $roomId 的解散通知，已即时从列表移除');
          _notifyRoomsChanged();
        }
        return;
      }

      final port = json["port"] as int;
      // 字段边界检查：广播是匿名的，畸形/恶意的大数值不能往下游传。
      if (port <= 0 || port > 65535) return;
      final cacheKey = includeOwnRoom
          ? '$roomId@${datagram.address.address}:$port'
          : roomId;

      final room = DiscoveredRoom(
        roomId: roomId,
        roomName: _clampText(json["roomName"] as String),
        hostNickname: _clampText(json["hostNickname"] as String),
        hostAddress: datagram.address,
        port: port,
        memberCount: ((json["members"] as int?) ?? 0).clamp(0, 99),
        applePeerService: applePeerService,
        lastSeen: DateTime.now(),
      );

      // 防伪造洪水：过期清理是 3.5 秒一次，短时间灌入大量假 roomId
      // 会把列表撑爆，超过上限的陌生房间直接不收。
      if (!_discoveredRooms.containsKey(cacheKey) &&
          _discoveredRooms.length >= maxDiscoveredRooms) {
        AppLog.warn(_tag, '发现列表已满（$maxDiscoveredRooms），忽略新房间 $roomId');
        return;
      }

      _discoveredRooms[cacheKey] = room;
      _ensurePruneTimer();
      _pruneStaleRooms();
      _notifyRoomsChanged();
    } catch (e) {
      AppLog.warn(_tag, '收到字段不完整的房间广播，已忽略', e);
    }
  }

  /// 广播字段截断：按字符数钳制，超长的房名/昵称不能进列表 UI。
  static String _clampText(String raw) {
    final trimmed = raw.trim();
    if (trimmed.length <= maxAdvertisedTextLength) return trimmed;
    return trimmed.substring(0, maxAdvertisedTextLength);
  }

  void _ensurePruneTimer() {
    if (_pruneTimer != null || _discoveredRooms.isEmpty) return;
    _pruneTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _pruneStaleRooms();
    });
  }

  void _pruneStaleRooms() {
    final now = DateTime.now();
    final countBefore = _discoveredRooms.length;
    _discoveredRooms.removeWhere(
      (_, room) => now.difference(room.lastSeen).inMilliseconds > 3500,
    );
    if (_discoveredRooms.length != countBefore) {
      _notifyRoomsChanged();
    }
    if (_discoveredRooms.isEmpty) {
      _pruneTimer?.cancel();
      _pruneTimer = null;
    }
  }

  void _notifyRoomsChanged() {
    if (_roomsController.isClosed) return;
    final signature = _discoveredRooms.values
        .map(
          (r) =>
              '${r.roomId}|${r.roomName}|${r.hostNickname}|'
              '${r.hostAddress.address}|${r.port}|${r.memberCount}|${r.applePeerService}',
        )
        .join(';');
    if (signature == _lastRoomsSignature) return;
    _lastRoomsSignature = signature;
    _roomsController.add(_discoveredRooms.values.toList());
  }

  Future<void> stop() async {
    final bonjourId = _bonjourId;
    final stopBonjour = _bonjourActive;
    _generation++;
    stopAdvertising();
    _bonjourActive = false;
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _socket?.close();
    _socket = null;
    _bonjourRefresh?.cancel();
    _bonjourRefresh = null;
    final subscription = _bonjourSubscription;
    _bonjourSubscription = null;
    _bonjourRooms.clear();
    _discoveredRooms.clear();
    _notifyRoomsChanged();
    await subscription?.cancel();
    if (_usesBonjour && stopBonjour) {
      await _bonjour
          .invokeMethod<void>('stop', {'magic': magic, 'id': bonjourId})
          .catchError((Object error) {
            AppLog.debug(_tag, '停止原生同网发现：$error');
          });
    }
  }

  void dispose() {
    _disposed = true;
    stop();
    _roomsController.close();
  }
}
