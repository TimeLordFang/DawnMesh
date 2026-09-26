import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../diagnostics/app_log.dart';
import '../diagnostics/pipeline_probe.dart';
import '../protocol/frame.dart';
import 'room_transport.dart';

const String _tag = '蓝牙';

enum BleRole { idle, hostPeripheral, clientCentral }

/// 扫描到的蓝牙房。
class DiscoveredBleRoom {
  final String address;
  final String roomName;

  /// L2CAP 通道号。由房主那侧的系统动态分配，从 BLE 广播里读出来。
  final int psm;
  final int memberCount;
  final int rssi;
  final DateTime lastSeen;

  DiscoveredBleRoom({
    required this.address,
    required this.roomName,
    required this.psm,
    required this.memberCount,
    required this.rssi,
    required this.lastSeen,
  });
}

/// 蓝牙房传输层：BLE L2CAP CoC（面向连接通道）。
///
/// 选它而不是经典蓝牙 RFCOMM 的原因：iOS 有 CBL2CAPChannel 对应物、不需要 MFi，
/// 鸿蒙 NEXT 也原生支持，是三端共用同一套协议的唯一选择。需要 Android 10（API 29）。
///
/// 注意 **PSM 不能写死**：它由房主那侧的系统在开监听时分配，通过 BLE 广播的
/// 厂商数据发布，客户端扫描时读取。这个类原先有一个 `defaultPsm = 0x1001`
/// 的常量，用它永远连不上。
///
/// 星型拓扑由房主转发：加密帧经会话认证后回到原生发送队列，
/// 保留语音实时标记；旧未加密控制帧仍由原生中继。
class BleL2capTransport implements RoomTransport, AuthenticatedRelayTransport {
  static const MethodChannel _channel = MethodChannel(
    'dev.dawnmesh.intercom/ble_l2cap',
  );
  static const EventChannel _dataChannel = EventChannel(
    'dev.dawnmesh.intercom/ble_l2cap_data',
  );
  static const EventChannel _scanChannel = EventChannel(
    'dev.dawnmesh.intercom/ble_l2cap_scan',
  );

  /// 扫描结果多久没再出现就认为房间已经消失。
  static const Duration _roomTtl = Duration(seconds: 6);

  BleRole _role = BleRole.idle;
  int _peerCount = 0;

  StreamSubscription? _dataSubscription;
  StreamSubscription? _scanSubscription;
  Timer? _pruneTimer;
  DiscoveredBleRoom? _lastConnectedRoom;
  bool _stopping = false;

  bool _sendErrorReported = false;
  final _frameSources = Expando<String>('BLE frame source');

  final Map<String, DiscoveredBleRoom> _rooms = {};
  final StreamController<Frame> _incoming = StreamController<Frame>.broadcast();
  final StreamController<List<DiscoveredBleRoom>> _roomsController =
      StreamController<List<DiscoveredBleRoom>>.broadcast();
  final StreamController<TransportDisconnection> _disconnections =
      StreamController<TransportDisconnection>.broadcast();

  @override
  Stream<Frame> get incoming => _incoming.stream;

  @override
  Stream<TransportDisconnection> get disconnections => _disconnections.stream;

  @override
  int get peerCount => _peerCount;

  Stream<List<DiscoveredBleRoom>> get roomsStream => _roomsController.stream;
  List<DiscoveredBleRoom> get currentRooms => _rooms.values.toList();

  BleRole get role => _role;
  bool get isHost => _role == BleRole.hostPeripheral;

  Future<bool> _ensurePermissions() async {
    if (!Platform.isAndroid) return true;
    try {
      final granted =
          await const MethodChannel('dev.dawnmesh.intercom/permissions')
              .invokeMethod<bool>('ensureBluetooth') ==
          true;
      if (!granted) AppLog.error(_tag, '需要附近设备权限；如已永久拒绝，请在系统应用设置中允许。');
      return granted;
    } on PlatformException catch (e) {
      AppLog.error(_tag, e.message ?? '无法申请蓝牙权限');
      return false;
    } on MissingPluginException {
      AppLog.error(_tag, '缺少 DawnMesh 安卓权限插件');
      return false;
    }
  }

  /// 本机能否开蓝牙房。不能的话返回的原因已经写进日志了。
  Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (e) {
      AppLog.error(_tag, '检查蓝牙能力失败', e);
      return false;
    }
  }

  // ------------------------------------------------------------------ 房主

  Future<bool> startHost({
    required String roomName,
    int memberCount = 1,
  }) async {
    if (!await _ensurePermissions()) return false;
    _role = BleRole.hostPeripheral;
    _sendErrorReported = false;
    await _listenIncomingData();

    try {
      final ok = await _channel.invokeMethod<bool>('startAdvertising', {
        'roomName': roomName,
        'memberCount': memberCount,
        'authenticatedRelay': true,
      });
      if (ok != true) {
        AppLog.error(_tag, '蓝牙房广播未能开启，其他人搜不到这个房间');
        _role = BleRole.idle;
        return false;
      }
      AppLog.info(_tag, '蓝牙房「$roomName」已开始广播');
      return true;
    } on PlatformException catch (e) {
      AppLog.error(_tag, e.message ?? '开启蓝牙房失败', e);
      _role = BleRole.idle;
      return false;
    } on MissingPluginException catch (e) {
      AppLog.error(_tag, '当前平台没有实现蓝牙通道', e);
      _role = BleRole.idle;
      return false;
    }
  }

  /// 人数变了要更新广播内容，扫描列表上的「N/6 台」才准。
  Future<void> updateMemberCount(int memberCount) async {
    if (!isHost) return;
    try {
      await _channel.invokeMethod('updateMemberCount', {
        'memberCount': memberCount,
      });
    } catch (e) {
      AppLog.debug(_tag, '更新广播人数失败：$e');
    }
  }

  // ---------------------------------------------------------------- 客户端

  Future<bool> startScan({bool recovering = false}) async {
    if (!await _ensurePermissions()) return false;
    _listenScanResults();

    try {
      final ok = await _channel.invokeMethod<bool>('startScan');
      if (ok != true) {
        if (recovering) {
          AppLog.warn('重连', '蓝牙扫描未能启动，等待系统蓝牙恢复');
        } else {
          AppLog.error(_tag, '蓝牙扫描未能启动，搜不到附近的蓝牙房');
        }
        return false;
      }
      _pruneTimer ??= Timer.periodic(
        const Duration(seconds: 2),
        (_) => _pruneStaleRooms(),
      );
      return true;
    } on PlatformException catch (e) {
      if (recovering) {
        AppLog.warn('重连', '重新扫描房主失败：${e.code} ${e.message ?? '未知系统错误'}');
      } else {
        AppLog.error(_tag, e.message ?? '蓝牙扫描失败', e);
      }
      return false;
    } on MissingPluginException catch (e) {
      AppLog.error(_tag, '当前平台没有实现蓝牙通道', e);
      return false;
    }
  }

  Future<void> stopScan() async {
    _pruneTimer?.cancel();
    _pruneTimer = null;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    _rooms.clear();
    _emitRooms();
    try {
      await _channel.invokeMethod('stopScan');
    } catch (e) {
      AppLog.debug(_tag, '停止蓝牙扫描失败：$e');
    }
  }

  Future<bool> connectToHost(
    DiscoveredBleRoom room, {
    bool silent = false,
  }) async {
    if (!await _ensurePermissions()) return false;
    _role = BleRole.clientCentral;
    _sendErrorReported = false;
    await _listenIncomingData();

    try {
      final ok = await _channel.invokeMethod<bool>('connectL2cap', {
        'address': room.address,
        'psm': room.psm,
      });
      if (ok != true) {
        if (!silent) AppLog.error(_tag, '连接蓝牙房主失败');
        _role = BleRole.idle;
        return false;
      }
      _peerCount = 1;
      _lastConnectedRoom = room;
      AppLog.info(_tag, '已连接蓝牙房「${room.roomName}」');
      return true;
    } on PlatformException catch (e) {
      if (silent) {
        AppLog.warn('重连', 'L2CAP 连接失败：${e.code} ${e.message ?? '未知系统错误'}');
      } else {
        AppLog.error(_tag, e.message ?? '连接蓝牙房主失败', e);
      }
      _role = BleRole.idle;
      return false;
    } on MissingPluginException catch (e) {
      AppLog.error(_tag, '当前平台没有实现蓝牙通道', e);
      _role = BleRole.idle;
      return false;
    }
  }

  /// 重新扫描原房间并使用最新地址与 PSM 恢复 L2CAP。
  ///
  /// Android 在蓝牙适配器关闭再开启后可能丢弃旧的 [BluetoothDevice] 状态，
  /// 隐私地址也可能变化。PSM 又是房主动态分配的，因此恢复时不能只复用首次
  /// 入房缓存。邀请码 PAKE 会在上层重新执行，即使附近出现同名房也无法冒充。
  Future<bool> reconnect() async {
    final previous = _lastConnectedRoom;
    if (previous == null) return false;
    await stop();

    AppLog.info('重连', '正在重新扫描蓝牙房主广播');
    final completer = Completer<DiscoveredBleRoom>();
    late final StreamSubscription<List<DiscoveredBleRoom>> subscription;
    subscription = roomsStream.listen((rooms) {
      for (final room in rooms) {
        if (room.address == previous.address ||
            room.roomName == previous.roomName) {
          if (!completer.isCompleted) completer.complete(room);
          return;
        }
      }
    });

    if (!await startScan(recovering: true)) {
      await subscription.cancel();
      return false;
    }

    DiscoveredBleRoom? refreshed;
    try {
      refreshed = await completer.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      AppLog.warn('重连', '5 秒内未重新发现原蓝牙房，稍后继续扫描');
    } finally {
      await subscription.cancel();
      await stopScan();
    }
    if (refreshed == null) return false;

    if (refreshed.address != previous.address ||
        refreshed.psm != previous.psm) {
      AppLog.info('重连', '已刷新房主广播参数（地址或 PSM 已变化），开始建立 L2CAP');
    } else {
      AppLog.info('重连', '已重新发现原蓝牙房，开始建立 L2CAP');
    }
    return connectToHost(refreshed, silent: true);
  }

  // ------------------------------------------------------------ RoomTransport

  @override
  void relayAuthenticated(Frame sealed, {required bool realtime}) {
    final source = _frameSources[sealed];
    if (!isHost || source == null) return;
    unawaited(
      _channel
          .invokeMethod<bool>('sendL2capData', {
            'data': sealed.encode(),
            'realtime': realtime,
            'excludeAddress': source,
          })
          .catchError((Object error) {
            AppLog.warn(_tag, '转发蓝牙帧失败', error);
            return false;
          }),
    );
  }

  @override
  void send(Frame frame, {bool realtime = false}) {
    if (_role == BleRole.idle) {
      AppLog.warn(_tag, '蓝牙通道未建立，${frame.type.name} 帧没有发出去');
      return;
    }

    final started = PipelineProbe.nowMicros();
    _channel
        .invokeMethod('sendL2capData', {
          'data': frame.encode(),
          'realtime': realtime,
        })
        .then((_) {
          PipelineProbe.record(
            realtime ? 'bleAudioMethod' : 'bleControlMethod',
            PipelineProbe.nowMicros() - started,
          );
        })
        .catchError((Object e) {
          PipelineProbe.record(
            realtime ? 'bleAudioMethodError' : 'bleControlMethodError',
            PipelineProbe.nowMicros() - started,
          );
          // 发送是高频路径，只报第一次。
          if (!_sendErrorReported) {
            _sendErrorReported = true;
            AppLog.error(_tag, '蓝牙数据发送失败，对方收不到语音', e);
          }
          return null;
        });
  }

  /// 转发在原生侧按链路地址完成，不需要成员号映射。
  @override
  void updateSelfMemberId(int id) {}

  /// 蓝牙按链路寻址，没有 UDP 那种自报成员号的白名单需求。
  @override
  void updateKnownMemberIds(Set<int> ids) {
    if (isHost) unawaited(updateMemberCount(ids.length));
  }

  /// BLE 帧经 invokeMethod 同步过桥，没有可刷写的本地缓冲。
  @override
  Future<void> flush() async {
    if (_role == BleRole.idle) return;
    try {
      await _channel.invokeMethod('flush').timeout(const Duration(seconds: 6));
    } catch (e) {
      AppLog.debug(_tag, '蓝牙发送队列清理失败：$e');
    }
  }

  /// 蓝牙房不支持房主转移。
  ///
  /// L2CAP 的 PSM 由系统在开监听时分配、经 BLE 广播发布，换房主意味着
  /// 新房主要重新开监听拿一个新 PSM、重新广播，其余人要全部重新扫描才能
  /// 发现它。这套流程一期不做——与旧版「主机退出即散会」的结论一致。
  @override
  bool get supportsHostTransfer => false;

  @override
  Map<int, String> get peerEndpoints => const {};

  @override
  Future<bool> becomeHost() async {
    AppLog.error(_tag, '蓝牙房暂不支持房主转移');
    return false;
  }

  @override
  Future<bool> reconnectToHost(String endpoint) async {
    AppLog.error(_tag, '蓝牙房暂不支持房主转移');
    return false;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _incoming.close();
    await _roomsController.close();
    await _disconnections.close();
  }

  @override
  Future<void> stop() async {
    _stopping = true;
    _role = BleRole.idle;
    _sendErrorReported = false;
    _peerCount = 0;

    await stopScan();
    await _dataSubscription?.cancel();
    _dataSubscription = null;
    _rooms.clear();

    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      AppLog.debug(_tag, '关闭蓝牙通道时被忽略的异常：$e');
    } finally {
      _stopping = false;
    }
  }

  // -------------------------------------------------------------------- 内部

  Future<void> _listenIncomingData() async {
    // EventChannel 原生端只有一个 sink。必须等旧订阅的 onCancel 完成后再
    // onListen；否则断线重连时旧 cancel 可能晚到，把新连接的 sink 清空，
    // 随后的 PAKE / roster 帧便永远到不了 Dart。
    await _dataSubscription?.cancel();
    _dataSubscription = _dataChannel.receiveBroadcastStream().listen((
      dynamic event,
    ) {
      if (event is! Map) {
        AppLog.warn(_tag, '收到非预期的蓝牙事件类型：${event.runtimeType}');
        return;
      }
      final eventType = event['type'] as String?;
      if (eventType == 'disconnected') {
        _peerCount = 0;
        final reason = event['reason'] as String? ?? 'unknown';
        final detail = event['detail'] as String?;
        final diagnostics = event['diagnostics'] as String?;
        AppLog.warn(
          _tag,
          '蓝牙房主链路断开：reason=$reason${diagnostics == null ? '' : '；$diagnostics'}',
          detail,
        );
        if (!_stopping && _role == BleRole.clientCentral) {
          _role = BleRole.idle;
          if (!_disconnections.isClosed) {
            _disconnections.add(
              TransportDisconnection(reason: reason, detail: detail),
            );
          }
        }
        return;
      }
      final data = event['data'] as Uint8List?;
      final peerAddress = event['peerAddress'] as String? ?? 'unknown';
      if (data == null) return;

      // 原生侧已经按帧头补齐成整帧了，这里直接解码即可。
      final decodeStarted = PipelineProbe.nowMicros();
      final frame = Frame.decode(data);
      PipelineProbe.record(
        'bleDartDecode',
        PipelineProbe.nowMicros() - decodeStarted,
      );
      if (frame == null) {
        AppLog.warn(_tag, '收到无法解析的蓝牙帧（${data.length} 字节），来自 $peerAddress');
        return;
      }
      _frameSources[frame] = peerAddress;
      if (!_incoming.isClosed) _incoming.add(frame);
    }, onError: (Object e) => AppLog.error(_tag, '蓝牙数据通道中断', e));
  }

  void _listenScanResults() {
    if (_scanSubscription != null) return;
    _scanSubscription = _scanChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is! Map) return;

        final address = event['address'] as String?;
        final psm = event['psm'] as int?;
        if (address == null || psm == null || psm < 1 || psm > 255) return;

        _rooms[address] = DiscoveredBleRoom(
          address: address,
          roomName: (event['roomName'] as String?) == '蓝牙房'
              ? (_rooms[address]?.roomName ?? '蓝牙房')
              : (event['roomName'] as String? ?? '蓝牙房'),
          psm: psm,
          memberCount: event['memberCount'] as int? ?? 1,
          rssi: event['rssi'] as int? ?? 0,
          lastSeen: DateTime.now(),
        );
        _emitRooms();
      },
      onError: (Object e) {
        AppLog.error(_tag, '蓝牙扫描出错，请稍后重新扫描：$e');
        unawaited(stopScan());
      },
    );
  }

  void _pruneStaleRooms() {
    final now = DateTime.now();
    final before = _rooms.length;
    _rooms.removeWhere((_, room) => now.difference(room.lastSeen) > _roomTtl);
    if (_rooms.length != before) _emitRooms();
  }

  void _emitRooms() {
    if (_roomsController.isClosed) return;
    _roomsController.add(_rooms.values.toList());
  }
}
