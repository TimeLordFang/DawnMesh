import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/audio/audio_io.dart';
import '../../core/preferences/nickname_store.dart';
import '../../core/security/room_invite.dart';
import '../widgets/room_invite_dialog.dart';
import '../../core/session/device_code.dart';
import '../../core/session/room_session.dart';
import '../../core/transport/ble_l2cap_transport.dart';
import '../../core/transport/lan_discovery.dart';
import '../../core/transport/lan_transport.dart';
import '../../core/transport/wifi_direct_manager.dart';
import '../../core/transport/wifi_direct_credentials.dart';
import '../theme/app_theme.dart';
import '../transitions/stage_choreography.dart';
import '../../core/update/update_service.dart';
import '../../l10n/app_strings.dart';

/// 首页前景：昵称、房型、建房/扫描按钮、附近房间列表。
///
/// 头部的日轮背景与大标题不在这里——它们归 `SessionStage` 管，因为进房时那层
/// 背景要留在原地继续演。这里只负责"会离场的那些东西"：每一块都套了
/// [StageExitItem]，按 [stage] 依次下沉淡出。
class HomeContent extends StatefulWidget {
  final bool isNight;

  /// 整段进房转场的 0→1 进度。0 时是完整首页，0.4 之后这里已经空了。
  /// 传的是动画本身而不是当帧的值——每行各自听，子树不用按帧重建。
  final Animation<double> stage;

  final AudioIo audioIo;
  final void Function(RoomSession session, String roomName) onEnterRoom;

  const HomeContent({
    super.key,
    required this.isNight,
    required this.stage,
    required this.audioIo,
    required this.onEnterRoom,
  });

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  final _nicknameController = TextEditingController();
  String? _defaultNickname;
  final _nicknameStore = NicknameStore();
  bool _nicknameEdited = false;
  bool _hasSavedNickname = false;

  Future<void> _restoreNickname() async {
    final saved = await _nicknameStore.load();
    if (!mounted || _nicknameEdited || saved == null) return;
    _hasSavedNickname = true;
    _nicknameController.text = saved;
  }

  void _saveNickname(String value) {
    _nicknameEdited = true;
    _hasSavedNickname = true;
    unawaited(_nicknameStore.save(value));
  }

  final _lanDiscovery = LanRoomDiscovery();
  final _bleDiscovery = BleL2capTransport();
  bool _busy = false;
  int _scanGeneration = 0;
  Future<void> _scanTask = Future<void>.value();
  RoomMode _selectedMode = RoomMode.wifiFullDuplex;
  bool _isScanning = false;
  List<WifiP2pPeer> _p2pPeers = [];

  Timer? _scanTimer;
  Timer? _periodicScanTimer;
  StreamSubscription<List<WifiP2pPeer>>? _p2pSubscription;
  bool _isHostingWifiDirect = false;

  @override
  void initState() {
    super.initState();
    widget.stage.addStatusListener(_onStageStatusChanged);
    _p2pSubscription = WifiDirectManager.instance.peersStream.listen((peers) {
      if (mounted) {
        setState(() {
          _p2pPeers = peers;
        });
      }
    });
    _startScan();
    unawaited(_restoreNickname());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nickname = AppStrings.of(context).defaultNickname;
    if (!_hasSavedNickname &&
        !_nicknameEdited &&
        (_defaultNickname == null ||
            _nicknameController.text == _defaultNickname)) {
      _nicknameController.text = nickname;
    }
    _defaultNickname = nickname;
  }

  void _onStageStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) {
      _stopPeriodicScan();
      _lanDiscovery.stopAdvertising();
      WifiDirectManager.instance.removeGroup();
      _isHostingWifiDirect = false;
    }
  }

  void _selectMode(RoomMode mode) {
    if (_busy || mode == _selectedMode) return;
    setState(() => _selectedMode = mode);
    _startScan();
  }

  Future<void> _startScan() {
    final generation = ++_scanGeneration;
    _scanTask = _scanTask.then((_) => _runScan(generation));
    return _scanTask;
  }

  Future<void> _stopBleScanning() async {
    _scanGeneration++;
    _scanTimer?.cancel();
    await _scanTask;
    await _bleDiscovery.stopScan();
    if (mounted) setState(() => _isScanning = false);
  }

  Future<void> _runScan(int generation) async {
    if (!mounted || generation != _scanGeneration) return;
    _scanTimer?.cancel();
    setState(() => _isScanning = true);
    if (_selectedMode == RoomMode.bluetoothPtt) {
      final ok = await _bleDiscovery.startScan();
      if (!mounted || generation != _scanGeneration) return;
      if (!ok) {
        setState(() => _isScanning = false);
        return;
      }
    } else {
      await _bleDiscovery.stopScan();
      if (!mounted || generation != _scanGeneration) return;
      _lanDiscovery.startListening();
      WifiDirectManager.instance.discoverPeers();
    }
    // BLE keeps receiving while this page is visible. The button is a refresh
    // indicator, not a loop that repeatedly registers a scanner (Android throttles it).
    _scanTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isScanning = false);
    });
  }

  void _showConnectionError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _bleRoomList(AppStrings s, Color textSecondary) {
    return StreamBuilder<List<DiscoveredBleRoom>>(
      stream: _bleDiscovery.roomsStream,
      initialData: _bleDiscovery.currentRooms,
      builder: (context, snapshot) {
        final rooms = snapshot.data ?? [];
        if (rooms.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '未发现蓝牙房。请让房主保持前台，确认两台手机已开启蓝牙并允许“附近设备”，然后重新扫描。',
              style: TextStyle(color: textSecondary),
            ),
          );
        }
        return Column(
          children: [
            for (final room in rooms)
              ListTile(
                leading: const Icon(Icons.bluetooth),
                title: Text(
                  room.roomName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('${room.memberCount}/6 · ${room.rssi} dBm'),
                trailing: TextButton(
                  onPressed:
                      _busy || room.memberCount >= 6
                          ? null
                          : () => _onJoinBleRoom(room),
                  child: Text(s.joinRoom),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _onJoinBleRoom(DiscoveredBleRoom room) async {
    if (_busy) return;
    setState(() => _busy = true);
    final invite = await requestRoomInvite(context);
    if (!mounted) return;
    if (invite == null) {
      setState(() => _busy = false);
      return;
    }
    await _stopBleScanning();
    if (!mounted) return;
    final transport = BleL2capTransport();
    if (!await transport.connectToHost(room)) {
      await transport.dispose();
      if (mounted) setState(() => _busy = false);
      _showConnectionError('连接蓝牙房失败，请重新扫描后重试。');
      return;
    }
    if (!mounted) {
      await transport.dispose();
      return;
    }
    final session = RoomSession(
      audioIo: widget.audioIo,
      selfNickname: _identityNickname,
      mode: RoomMode.bluetoothPtt,
    );
    await session.protectWithInvite(invite);
    session.transport = transport;
    session.onSendFrame = transport.send;
    transport.incoming.listen(session.handleIncomingFrame);
    final joined = session.stateStream
        .firstWhere((state) => state == RoomState.inRoom)
        .timeout(const Duration(seconds: 8));
    await session.joinRoom(startAudio: false);
    try {
      await joined;
    } on TimeoutException {
      await session.dispose();
      if (mounted) setState(() => _busy = false);
      _showConnectionError('入房验证失败，请确认邀请码正确且房主仍在线。');
      return;
    }
    if (!mounted) {
      await session.dispose();
      return;
    }
    setState(() => _busy = false);
    widget.onEnterRoom(session, room.roomName);
  }

  void _startPeriodicScan() {
    _periodicScanTimer?.cancel();
    _periodicScanTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted && _isHostingWifiDirect) {
        WifiDirectManager.instance.discoverPeers();
      }
    });
  }

  void _stopPeriodicScan() {
    _periodicScanTimer?.cancel();
    _periodicScanTimer = null;
  }

  @override
  void dispose() {
    widget.stage.removeStatusListener(_onStageStatusChanged);
    _scanTimer?.cancel();
    _periodicScanTimer?.cancel();
    _p2pSubscription?.cancel();
    _nicknameController.dispose();
    _scanGeneration++;
    unawaited(_scanTask.then((_) => _bleDiscovery.dispose()));
    _lanDiscovery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isNight = widget.isNight;
    final stage = widget.stage;
    final textPrimary =
        isNight ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondary =
        isNight ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    final cardBg = isNight ? AppTheme.darkCardBg : AppTheme.lightCardBg;

    return SafeArea(
      top: false,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 18),

                  // 1. 昵称输入
                  StageExitItem(
                    stage: stage,
                    index: 0,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color:
                                isNight
                                    ? const Color(0xFF283A52)
                                    : const Color(0xFFDCCEC8),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 24,
                              color: textSecondary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _nicknameController,
                                onChanged: _saveNickname,
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 17,
                                ),
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  hintText: s.nicknamePlaceholder,
                                  hintStyle: TextStyle(
                                    color: textSecondary,
                                    fontSize: 17,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message:
                                  '${s.deviceCodeTooltip} (#${DeviceCode.current})',
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: (isNight
                                          ? AppTheme.nightSkyBlue
                                          : AppTheme.sunsetCoral)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '#${DeviceCode.current}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                    color:
                                        isNight
                                            ? AppTheme.nightSkyBlue
                                            : AppTheme.sunsetCoral,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // 2. 房型选择（WiFi 房 / 蓝牙房）
                  StageExitItem(
                    stage: stage,
                    index: 1,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      // IntrinsicHeight + stretch：两张卡等高，以内容较多的
                      // 那张为准；否则中英文折行数不同时一高一低不齐整。
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _ModeSelectChip(
                                icon: Icons.wifi,
                                title: s.wifiRoom,
                                subtitle: s.wifiRoomChipSubtitle,
                                isSelected:
                                    _selectedMode == RoomMode.wifiFullDuplex,
                                isNight: isNight,
                                onTap:
                                    () => _selectMode(RoomMode.wifiFullDuplex),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _ModeSelectChip(
                                icon: Icons.bluetooth,
                                title: s.bluetoothRoom,
                                subtitle: s.bleRoomChipSubtitle,
                                isSelected:
                                    _selectedMode == RoomMode.bluetoothPtt,
                                isNight: isNight,
                                onTap: () => _selectMode(RoomMode.bluetoothPtt),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Text('语音和聊天默认加密。加入需要房主的邀请码，请仅分享给信任的人。'),
                  ),
                  const SizedBox(height: 18),

                  // 3. 建房 + 扫描
                  StageExitItem(
                    stage: stage,
                    index: 2,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 6,
                            child: ElevatedButton(
                              onPressed: _busy ? null : _onCreateRoom,
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    isNight
                                        ? AppTheme.nightSkyBlue
                                        : AppTheme.sunsetBurgundy,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 18,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                elevation: 0,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _selectedMode == RoomMode.wifiFullDuplex
                                      ? s.createWifiRoom
                                      : s.createBleRoom,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 5,
                            child: OutlinedButton(
                              onPressed:
                                  _isScanning || _busy ? null : _startScan,
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color:
                                      isNight
                                          ? AppTheme.nightSkyBlue
                                          : AppTheme.sunsetCoral,
                                  width: 1.6,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 18,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_isScanning)
                                      SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color:
                                              isNight
                                                  ? AppTheme.moonSilverWhite
                                                  : AppTheme.sunsetCoral,
                                        ),
                                      )
                                    else
                                      Icon(
                                        Icons.radar,
                                        size: 21,
                                        color:
                                            isNight
                                                ? AppTheme.moonSilverWhite
                                                : AppTheme.sunsetCoral,
                                      ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _isScanning ? s.scanning : s.scanRooms,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color:
                                            isNight
                                                ? AppTheme.moonSilverWhite
                                                : AppTheme.sunsetCoral,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  // 4. 房间列表标题
                  StageExitItem(
                    stage: stage,
                    index: 3,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              s.nearbyRoomsTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (_isScanning) ...[
                            const SizedBox(width: 8),
                            Text(
                              s.detectingRooms,
                              style: TextStyle(
                                color:
                                    isNight
                                        ? AppTheme.nightSkyBlue
                                        : AppTheme.sunsetCoral,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),
                ],
              ),
            ),

            // 5. 房间列表
            SliverToBoxAdapter(
              child: StageExitItem(
                stage: stage,
                index: 4,
                child:
                    _selectedMode == RoomMode.bluetoothPtt
                        ? _bleRoomList(s, textSecondary)
                        : StreamBuilder<List<DiscoveredRoom>>(
                          stream: _lanDiscovery.roomsStream,
                          initialData: _lanDiscovery.currentRooms,
                          builder: (context, snapshot) {
                            final rooms = snapshot.data ?? [];
                            final p2pPeers = _p2pPeers;
                            final totalCount = rooms.length + p2pPeers.length;

                            if (totalCount == 0) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 32,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  s.noRoomsDiscoveredHint,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: textSecondary.withValues(alpha: 0.7),
                                    fontSize: 15,
                                    height: 1.5,
                                  ),
                                ),
                              );
                            }

                            return ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 8,
                              ),
                              itemCount: totalCount,
                              separatorBuilder:
                                  (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                if (index < rooms.length) {
                                  final room = rooms[index];
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cardBg,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color:
                                            isNight
                                                ? const Color(0xFF283A52)
                                                : const Color(0xFFDCCEC8),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                room.roomName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: textPrimary,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                s.roomHostInfo(
                                                  room.hostNickname,
                                                  room.memberCount,
                                                  6,
                                                ),
                                                style: TextStyle(
                                                  color: textSecondary,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        ElevatedButton(
                                          onPressed: () => _onJoinRoom(room),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                isNight
                                                    ? AppTheme.nightSkyBlue
                                                    : AppTheme.sunsetCoral,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 22,
                                              vertical: 14,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(22),
                                            ),
                                          ),
                                          child: Text(
                                            s.joinRoom,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                } else {
                                  final peer = p2pPeers[index - rooms.length];
                                  final peerTitle =
                                      peer.name.isNotEmpty
                                          ? s.defaultWifiRoomTitle(peer.name)
                                          : s.nearbyWifiRoom;
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cardBg,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color:
                                            isNight
                                                ? const Color(0xFF283A52)
                                                : const Color(0xFFDCCEC8),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                peerTitle,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: textPrimary,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                "${s.hostTag}: ${peer.name.isNotEmpty ? peer.name : s.nearbyDevice} · ${s.nearFieldDirect}",
                                                style: TextStyle(
                                                  color: textSecondary,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        ElevatedButton(
                                          onPressed:
                                              () => _onJoinWifiDirectPeer(peer),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                isNight
                                                    ? AppTheme.nightSkyBlue
                                                    : AppTheme.sunsetCoral,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 22,
                                              vertical: 14,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(22),
                                            ),
                                          ),
                                          child: Text(
                                            s.joinRoom,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              },
                            );
                          },
                        ),
              ),
            ),

            // 6. 版本号（随首页元素自然离场）
            SliverToBoxAdapter(
              child: StageExitItem(
                stage: stage,
                index: 5,
                drift: 24,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 36),
                  child: Center(
                    child: Text(
                      'v${UpdateService.currentVersion}',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: textSecondary.withValues(alpha: 0.5),
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _nickname {
    final s = AppStrings.of(context);
    final text = _nicknameController.text.trim();
    if (text.isEmpty) return s.defaultNickname;
    var nickname = '';
    for (final rune in text.runes) {
      final candidate = nickname + String.fromCharCode(rune);
      if (utf8.encode(candidate).length > 48) break;
      nickname = candidate;
    }
    return nickname;
  }

  /// 走 roster 的身份名，带十六进制短码，房间里好区分同名的人。
  /// 房名仍然用不带码的昵称，免得标题变得很长。
  String get _identityNickname => DeviceCode.attach(_nickname);

  void _onCreateRoom() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _stopBleScanning();
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    final s = AppStrings.of(context);
    final nickname = _nickname;
    final roomName =
        _selectedMode == RoomMode.wifiFullDuplex
            ? s.defaultWifiRoomTitle(nickname)
            : s.defaultBleRoomTitle(nickname);

    final session = RoomSession(
      audioIo: widget.audioIo,
      selfNickname: _identityNickname,
      mode: _selectedMode,
    );

    final invite = RoomInvite.generate();
    await session.protectWithInvite(invite);
    if (!mounted) {
      await session.dispose();
      return;
    }

    if (_selectedMode == RoomMode.wifiFullDuplex) {
      _isHostingWifiDirect = true;
      unawaited(
        WifiDirectManager.instance.createGroup(
          WifiDirectCredentials.fromInvite(invite),
        ),
      );
      _startPeriodicScan();
      final transport = LanTransport(controlOnly: true);
      if (!await transport.startHost()) {
        await transport.dispose();
        _stopPeriodicScan();
        await WifiDirectManager.instance.removeGroup();
        _isHostingWifiDirect = false;
        if (mounted) setState(() => _busy = false);
        _showConnectionError('无法开启 Wi-Fi 房间，请检查网络和端口占用。');
        return;
      }
      session.transport = transport;
      session.onSendFrame = transport.send;
      transport.incoming.listen(session.handleIncomingFrame);
    } else {
      final transport = BleL2capTransport();
      if (!await transport.startHost(roomName: roomName)) {
        await transport.dispose();
        if (mounted) setState(() => _busy = false);
        _showConnectionError('蓝牙广播未能开启。请检查蓝牙和附近设备权限后重试。');
        return;
      }
      session.transport = transport;
      session.onSendFrame = transport.send;
      transport.incoming.listen(session.handleIncomingFrame);
    }

    // 不在这里开麦：AudioRecord/AudioTrack 的构造压在 Android 主线程上，
    // 一次上百毫秒，塞进转场会掉帧。SessionStage 会在动画落位后调 startAudio。
    await session.createRoom(startAudio: false);

    if (_selectedMode == RoomMode.wifiFullDuplex) {
      _lanDiscovery.startAdvertising(
        roomId: "room_${DateTime.now().millisecondsSinceEpoch}",
        roomName: roomName,
        hostNickname: _identityNickname,
        tcpPort: 8988,
        getMemberCount: () => session.members.length,
      );
    }

    if (!mounted) {
      await session.dispose();
      return;
    }
    setState(() => _busy = false);
    widget.onEnterRoom(session, roomName);
  }

  void _onJoinRoom(DiscoveredRoom room) async {
    if (_busy) return;
    setState(() => _busy = true);
    final invite = await requestRoomInvite(context);
    if (!mounted) return;
    if (invite == null) {
      setState(() => _busy = false);
      return;
    }
    FocusScope.of(context).unfocus();
    final session = RoomSession(
      audioIo: widget.audioIo,
      selfNickname: _identityNickname,
      mode: RoomMode.wifiFullDuplex,
    );

    final transport = LanTransport(controlOnly: true);
    if (!await transport.startClient(
      hostAddress: room.hostAddress,
      port: room.port,
    )) {
      await transport.dispose();
      if (mounted) setState(() => _busy = false);
      _showConnectionError('连接 Wi-Fi 房失败，请重新扫描后重试。');
      return;
    }
    await session.protectWithInvite(invite);
    session.transport = transport;
    session.onSendFrame = transport.send;
    transport.incoming.listen(session.handleIncomingFrame);

    // 同 _onCreateRoom：开麦推迟到转场跑完。
    final joined = session.stateStream
        .firstWhere((state) => state == RoomState.inRoom)
        .timeout(const Duration(seconds: 8));
    await session.joinRoom(startAudio: false);
    try {
      await joined;
    } on TimeoutException {
      await session.dispose();
      if (mounted) setState(() => _busy = false);
      _showConnectionError('入房验证失败，请确认邀请码正确且房主仍在线。');
      return;
    }

    if (!mounted) {
      await session.dispose();
      return;
    }
    setState(() => _busy = false);
    widget.onEnterRoom(session, room.roomName);
  }

  void _onJoinWifiDirectPeer(WifiP2pPeer peer) async {
    if (_busy) return;
    setState(() => _busy = true);
    final invite = await requestRoomInvite(context);
    if (!mounted) return;
    if (invite == null) {
      setState(() => _busy = false);
      return;
    }
    FocusScope.of(context).unfocus();
    final s = AppStrings.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          s.connectingTo(peer.name.isNotEmpty ? peer.name : peer.address),
        ),
        duration: const Duration(seconds: 4),
      ),
    );

    final connectionInfo = await WifiDirectManager.instance.connectAndWait(
      peer.address,
      credentials: WifiDirectCredentials.fromInvite(invite),
    );
    if (connectionInfo == null ||
        !connectionInfo.isConnected ||
        connectionInfo.groupOwnerAddress.isEmpty) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.directConnectPermissionFailed),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    final hostIp = InternetAddress(connectionInfo.groupOwnerAddress);
    final session = RoomSession(
      audioIo: widget.audioIo,
      selfNickname: _identityNickname,
      mode: RoomMode.wifiFullDuplex,
    );

    final transport = LanTransport(controlOnly: true);
    if (!await transport.startClient(hostAddress: hostIp, port: 8988)) {
      await transport.dispose();
      if (mounted) setState(() => _busy = false);
      _showConnectionError('已连接 Wi-Fi Direct，但房间服务不可用。');
      return;
    }
    await session.protectWithInvite(invite);
    session.transport = transport;
    session.onSendFrame = transport.send;
    transport.incoming.listen(session.handleIncomingFrame);

    final joined = session.stateStream
        .firstWhere((state) => state == RoomState.inRoom)
        .timeout(const Duration(seconds: 8));
    await session.joinRoom(startAudio: false);
    try {
      await joined;
    } on TimeoutException {
      await session.dispose();
      if (mounted) setState(() => _busy = false);
      _showConnectionError('入房验证失败，请确认邀请码正确且房主仍在线。');
      return;
    }

    if (!mounted) {
      await session.dispose();
      return;
    }
    if (mounted) {
      setState(() => _busy = false);
      final displayName =
          peer.name.isNotEmpty ? s.defaultWifiRoomTitle(peer.name) : s.wifiRoom;
      widget.onEnterRoom(session, displayName);
    }
  }
}

class _ModeSelectChip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final bool isNight;
  final VoidCallback onTap;

  const _ModeSelectChip({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.isNight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor =
        isNight ? AppTheme.nightSkyBlue : AppTheme.sunsetBurgundy;
    final cardBg = isNight ? AppTheme.darkCardBg : AppTheme.lightCardBg;
    final textPrimary =
        isNight ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondary =
        isNight ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.12) : cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color:
                isSelected
                    ? activeColor
                    : (isNight
                        ? const Color(0xFF283A52)
                        : const Color(0xFFDCCEC8)),
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected ? activeColor : textSecondary,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 2,
                    style: TextStyle(
                      color: isSelected ? activeColor : textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(color: textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
