import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import '../audio/audio_io.dart';
import '../audio/voice_activity_gate.dart';
import '../platform/background_call_controls.dart';
import '../platform/platform_audio_channel.dart';
import '../diagnostics/app_log.dart';
import '../protocol/frame.dart';
import '../protocol/frame_type.dart';
import '../protocol/payloads/chat_delete.dart';
import '../protocol/payloads/chat_message.dart';
import '../protocol/payloads/chat_sync.dart';
import '../protocol/payloads/join_request.dart';
import '../protocol/payloads/leave.dart';
import '../protocol/payloads/ptt_state.dart';
import '../protocol/payloads/roster.dart';
import '../security/session_handshake.dart';
import '../security/room_invite.dart';
import '../security/room_admission.dart';
import '../transport/room_transport.dart';
import 'chat_message.dart';
import 'device_code.dart';
import 'host_transfer.dart';
import 'member.dart';
import 'reconnect_controller.dart';

enum RoomMode { wifiFullDuplex, bluetoothPtt }

enum VoiceMode { pushToTalk, automatic }

enum RoomState { idle, connecting, inRoom, reconnecting, disconnected }

/// Full Feature-Parity Central Room Session Controller.
class RoomSession {
  /// 全双工模式下没有 PTT 的「松手」事件，只能靠音频停流判断对方说完了。
  static const Duration _speakingTimeout = Duration(milliseconds: 400);

  /// 上行 Opus 码率。蓝牙房必须压低——BLE L2CAP 扛不住 24k 再乘以转发份数。
  static const int _wifiBitrate = 24000;
  static const int _bluetoothBitrate = 16000;

  /// 纯内存聊天历史上限
  static const int maxChatHistory = 100;

  /// (senderId, seq) 有界去重队列容量
  static const int maxDeduplicationKeys = 512;

  /// 房主为掉线成员保留 10 分钟名额和 sessionToken 身份。
  /// 这样遮挡、锁屏省电或 Wi-Fi Direct 短暂掉组不会把成员踢出房间。
  static const Duration _memberTimeout = Duration(minutes: 10);

  /// 客户端允许至少 6 次心跳调度抖动；任意来自房主的合法帧都会续期。
  static const Duration _hostSilenceBeforeReconnect = Duration(seconds: 12);

  final AudioIo audioIo;
  final String selfNickname;
  final Uint8List sessionToken;
  final RoomMode mode;
  late VoiceMode _voiceMode =
      mode == RoomMode.wifiFullDuplex
          ? VoiceMode.automatic
          : VoiceMode.pushToTalk;
  VoiceMode get voiceMode => _voiceMode;
  bool get isBluetooth => mode == RoomMode.bluetoothPtt;
  final _voiceGate = VoiceActivityGate();
  final _controlsController = StreamController<void>.broadcast();
  Stream<void> get controlsStream => _controlsController.stream;
  BackgroundCallControls? _backgroundControls;

  void setVoiceMode(VoiceMode value) {
    if (_closed || _voiceMode == value) return;
    setPtt(false);
    _voiceMode = value;
    _voiceGate.reset();
    _notifyControls();
  }

  void _notifyControls() {
    if (!_controlsController.isClosed) _controlsController.add(null);
    unawaited(
      _backgroundControls?.update(
        bluetooth: isBluetooth,
        automatic: isFullDuplex,
        pressed: isPttPressed,
        muted: isMuted,
      ),
    );
  }

  /// Production entry points require a fresh room invitation before connecting.
  /// Nullable only for legacy protocol tests and explicit internal use.
  SecureFrameCodec? secureCodec;
  RoomInvite? roomInvite;
  RoomAdmission? _admission;
  bool _admitted = false;
  bool _closed = false;
  Future<void> _incomingQueue = Future.value();
  Future<void> _outgoingQueue = Future.value();
  int _pendingIncoming = 0;
  int _pendingOutgoing = 0;

  Future<void> protectWithInvite(RoomInvite invite) async {
    roomInvite = invite;
    _admission = RoomAdmission(
      passwordScalar: await invite.passwordScalar(),
      token: sessionToken,
      send: (frame) => onSendFrame?.call(frame),
      onReady: (codec) async {
        if (_closed) return;
        secureCodec = codec;
        if (!_isHost) await _sendJoinRequest();
      },
    );
  }

  // Leave room for the largest chat-history header when encryption is enabled.
  int get maxChatTextBytes => secureCodec == null ? 480 : 320;

  RoomState _state = RoomState.idle;
  bool _isHost = false;
  int _selfMemberId = 1;
  int _seq = 0;

  /// 传输层。房主转移要靠它取对端端点、接任监听、重连到新房主。
  RoomTransport? transport;

  /// 房主分配 joinOrder 用的单调计数器（房主自己是 0）。
  int _nextJoinOrder = 1;

  /// 最近一次收到的交接快照。房主猝死时全靠它自行迁移——
  /// 这正是旧版 HOST_SNAPSHOT(8) 存在的意义。
  HostTransferPlan? _cachedPlan;

  /// 见过的最大 joinOrder，用来丢弃迟到或被重放的旧计划。
  /// joinOrder 由房主单调分配，所以更新的计划一定不会更小。
  int _highestSeenJoinOrder = 0;

  /// 交接执行中，避免 2 秒一次的心跳把同一次迁移重复触发。
  bool _transferInProgress = false;

  final Map<int, Member> _members = {};

  /// 每个成员最后一次送到音频帧的时间，用来判断说话是否已经结束。
  final Map<int, DateTime> _lastAudioAt = {};
  Timer? _speakingWatchTimer;
  Timer? _heartbeatTimer;
  StreamSubscription<Frame>? _transportIncomingSubscription;
  StreamSubscription<TransportDisconnection>? _transportDisconnectSubscription;
  Future<bool> Function()? _reconnectTransport;

  /// 麦克风/扬声器是否已经打开，[startAudio] 用它做幂等。
  bool _audioStarted = false;
  late ReconnectController _reconnectController;

  // 纯内存聊天状态
  final List<ChatMessage> _chatMessages = [];
  final _chatStreamController = StreamController<ChatMessage>.broadcast(
    sync: true,
  );
  final _chatListController = StreamController<List<ChatMessage>>.broadcast(
    sync: true,
  );
  final _unreadStreamController = StreamController<int>.broadcast(sync: true);
  int _unreadChatCount = 0;
  final Set<String> _seenChatKeys = <String>{};
  final List<String> _seenChatKeyOrder = <String>[];

  // 跨进退房同人身份与曾用名追踪 (基于设备短码)
  final Map<String, String> _currentNicknameByCode = {};
  final Map<String, Set<String>> _previousNicknamesByCode = {};

  // UI Reactive Streams
  final _stateController = StreamController<RoomState>.broadcast();
  final _membersController = StreamController<List<Member>>.broadcast();
  final _waveController = StreamController<double>.broadcast();

  // 音浪只喂 UI，33ms 一帧（约 30Hz）足够顺滑。采集回调本身 25~50Hz，
  // 不限频的话背景水波和对讲盘的重绘节奏会被音频帧拖着走，转场期间抢帧。
  int _lastWaveUiEmitMs = 0;

  Stream<RoomState> get stateStream => _stateController.stream;
  Stream<List<Member>> get membersStream => _membersController.stream;
  Stream<double> get waveStream => _waveController.stream;
  Stream<ChatMessage> get chatStream => _chatStreamController.stream;
  Stream<List<ChatMessage>> get chatListStream => _chatListController.stream;
  List<ChatMessage> get chatMessages => List.unmodifiable(_chatMessages);
  Stream<int> get unreadChatStream => _unreadStreamController.stream;
  int get unreadChatCount => _unreadChatCount;

  RoomState get state => _state;
  bool get isHost => _isHost;
  bool get isMuted => audioIo.isMuted;
  bool isPttPressed = false;
  int get selfMemberId => _selfMemberId;
  List<Member> get members => _members.values.toList();
  bool get isFullDuplex => _voiceMode == VoiceMode.automatic;

  /// 会话令牌：进房时随机生成，同一台设备跨重连保持不变。
  /// 房主用它判定「老成员重连回来了」——昵称谁都可以填一样的，不能作为身份依据。
  ///
  /// 不再默认全零：全零令牌会让所有客户端在房主侧长得一模一样，令牌判定就失效了。
  RoomSession({
    required this.audioIo,
    required this.selfNickname,
    this.mode = RoomMode.wifiFullDuplex,
    Uint8List? sessionToken,
  }) : sessionToken = sessionToken ?? _generateSessionToken() {
    _reconnectController = ReconnectController(
      onAttemptReconnect: _attemptReconnect,
      onMaxRetriesReached: () {
        unawaited(_finishReconnectWindow());
      },
    );
  }

  /// 绑定传输层及它的真实断链通知。重连闭包负责恢复物理链路，随后本类
  /// 会重新执行邀请码 PAKE 和入房流程，沿用 sessionToken 认领原身份。
  void attachTransport(
    RoomTransport value, {
    required Future<bool> Function() reconnect,
  }) {
    _transportIncomingSubscription?.cancel();
    _transportDisconnectSubscription?.cancel();
    transport = value;
    onSendFrame = value.send;
    _reconnectTransport = reconnect;
    _transportIncomingSubscription = value.incoming.listen(handleIncomingFrame);
    _transportDisconnectSubscription = value.disconnections.listen(
      _handleTransportDisconnection,
    );
  }

  static Uint8List _generateSessionToken() {
    final token = Uint8List(16);
    final rng = Random.secure();
    for (int i = 0; i < token.length; i++) {
      token[i] = rng.nextInt(256);
    }
    return token;
  }

  /// 全零令牌是旧版客户端的默认值，不能作为唯一身份。
  static bool _isZeroToken(Uint8List token) => token.every((b) => b == 0);

  static bool _tokensEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Create a new room as Host.
  ///
  /// [startAudio] 为 false 时不开麦，需要之后手动调用 [startAudio]。
  /// 进房转场期间要用它把开麦推迟到动画结束——原因见 [startAudio] 的说明。
  Future<void> createRoom({bool startAudio = true}) async {
    _isHost = true;
    await _admission?.startHost();
    _selfMemberId = 1;
    _members.clear();
    _nextJoinOrder = 1;
    _cachedPlan = null;
    _highestSeenJoinOrder = 0;

    final selfMember = Member(
      memberId: _selfMemberId,
      nickname: selfNickname,
      sessionToken: sessionToken,
      joinOrder: 0, // 房主永远是资历最老的那个
      isHost: true,
    );
    _members[_selfMemberId] = selfMember;
    _recordMemberIdentity(_selfMemberId, selfNickname);

    _updateState(RoomState.inRoom);
    _notifyMembers();
    _syncKnownMembersToTransport();

    if (startAudio) await this.startAudio();
    _startHeartbeat();
  }

  /// Join an existing room as Client.
  Future<void> joinRoom({bool startAudio = true}) async {
    _isHost = false;
    _admitted = false;
    _selfMemberId = 0;
    _members.clear();

    _updateState(RoomState.connecting);

    if (_admission != null) {
      _admission!.startClient();
    } else {
      await _sendJoinRequest();
    }
    if (startAudio && roomInvite == null) await this.startAudio();
    _startHeartbeat();
  }

  Future<void> _sendJoinRequest() async {
    final joinPayload = JoinRequestPayload(
      nickname: selfNickname,
      sessionToken: sessionToken,
    );
    final joinFrame = Frame(
      type: FrameType.joinReq,
      senderId: 0,
      seq: _nextSeq(),
      payload: joinPayload.encode(),
    );
    await sendFrame(joinFrame);
  }

  /// 打开麦克风与扬声器。可重复调用，只生效一次。
  ///
  /// 之所以能和建房/加入分开：`AudioRecord` / `AudioTrack` 的构造、AEC/NS/AGC
  /// 挂载、前台服务启动全都发生在 **Android 主线程**上，一次上百毫秒。
  /// 如果压在 560ms 的进房转场里，UI 线程和平台线程互相抢，动画必然掉帧。
  /// 所以进房时先只建房、跑完动画再开麦。
  Future<void> startAudio() async {
    if (_audioStarted ||
        _closed ||
        (roomInvite != null && _state != RoomState.inRoom)) {
      return;
    }
    _audioStarted = true;
    if (audioIo is PlatformAudioChannel) {
      _backgroundControls = BackgroundCallControls(this);
      await _backgroundControls!.bind((command, value) async {
        if (_closed || !_audioStarted) return;
        if (command == 'ptt') setPtt(value == true);
        if (command == 'automatic') {
          setVoiceMode(
            value == true ? VoiceMode.automatic : VoiceMode.pushToTalk,
          );
        }
        if (command == 'mute' && value is bool && value != isMuted) {
          toggleMute();
        }
      });
      _notifyControls();
    }
    await _startAudioPipeline();
  }

  /// Process incoming binary frames
  Future<void> handleIncomingFrame(Frame frame) {
    if (_closed) return Future.value();
    if (secureCodec == null && roomInvite == null) {
      return _handleIncomingFrame(frame);
    }
    // Keep async cryptography in wire order and bound unauthenticated work.
    if (_pendingIncoming >= 256) return Future.value();
    _pendingIncoming++;
    final next = _incomingQueue
        .then((_) async {
          if (!_closed) await _handleIncomingFrame(frame);
        })
        .whenComplete(() => _pendingIncoming--);
    _incomingQueue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _handleIncomingFrame(Frame frame) async {
    if (roomInvite != null &&
        (frame.type == FrameType.handshakeHello ||
            frame.type == FrameType.handshakeConfirm)) {
      try {
        await _admission?.handle(frame);
      } catch (_) {
        /* Invalid admission is rejected. */
      }
      return;
    }
    if (roomInvite != null && secureCodec == null) return;
    if (frame.type == FrameType.sealed) {
      if (secureCodec == null) {
        AppLog.warn('RoomSession', '收到加密帧但未配置安全编解码器，已丢弃');
        return;
      }
      try {
        final opened = await secureCodec!.open(frame);
        if (opened.type == FrameType.sealed ||
            opened.type == FrameType.handshakeHello ||
            opened.type == FrameType.handshakeConfirm) {
          return;
        }
        await _dispatchIncomingFrame(opened);
      } catch (e) {
        AppLog.error('RoomSession', '解封加密帧失败，可能为伪造或重放帧', e);
      }
      return;
    }

    if (secureCodec != null) {
      AppLog.warn('RoomSession', '已启用加密，拒绝未密封的入站帧');
      return;
    }
    await _dispatchIncomingFrame(frame);
  }

  Future<void> _dispatchIncomingFrame(Frame frame) async {
    if (secureCodec != null) {
      final hostCommand =
          frame.type == FrameType.roster ||
          frame.type == FrameType.hostHandover ||
          frame.type == FrameType.hostAnnounce ||
          frame.type == FrameType.chatSync;
      if (hostCommand && (_isHost || frame.senderId != 1)) return;
    }
    if (roomInvite != null &&
        !_isHost &&
        !_admitted &&
        frame.type != FrameType.admission) {
      return;
    }
    _markAuthenticatedHostActivity(frame);
    switch (frame.type) {
      case FrameType.admission:
        if (roomInvite != null &&
            !_isHost &&
            frame.senderId == 1 &&
            frame.payload.length == 17 &&
            frame.payload[0] >= 2 &&
            frame.payload[0] <= 6 &&
            _tokensEqual(frame.payload.sublist(1), sessionToken)) {
          _admitted = true;
          _selfMemberId = frame.payload[0];
          transport?.updateSelfMemberId(_selfMemberId);
        }
        break;
      case FrameType.audio:
        _handleAudioFrame(frame);
        break;
      case FrameType.joinReq:
        _handleJoinReq(frame);
        break;
      case FrameType.roster:
        _handleRoster(frame);
        break;
      case FrameType.pttState:
        _handlePttState(frame);
        break;
      case FrameType.heartbeat:
        _handleHeartbeat(frame);
        break;
      case FrameType.leave:
        _handleLeave(frame);
        break;
      case FrameType.hostHandover:
        await _handleHostHandover(frame);
        break;
      case FrameType.hostAnnounce:
        _handleHostAnnounce(frame);
        break;
      case FrameType.chat:
        _handleChatFrame(frame);
        break;
      case FrameType.chatSync:
        _handleChatSyncFrame(frame);
        break;
      case FrameType.chatDelete:
        _handleChatDeleteFrame(frame);
        break;
      case FrameType.handshakeHello:
      case FrameType.handshakeConfirm:
      case FrameType.sealed:
        break;
    }
  }

  void _markAuthenticatedHostActivity(Frame frame) {
    if (_isHost) return;
    for (final member in _members.values) {
      if (member.isHost && member.memberId == frame.senderId) {
        member.lastActiveAt = DateTime.now();
        return;
      }
    }
  }

  void _handleAudioFrame(Frame frame) {
    if (frame.senderId == _selfMemberId) return;

    // 只收在册成员的音频：否则任何陌生或伪造的 senderId 都能在原生侧
    // 凭空建出一路抖动缓冲和解码器，且永远不会被回收。
    final sender = _members[frame.senderId];
    if (sender == null) return;

    // 整帧原样交给原生播放管线：那边从帧头解析发送方与序号，
    // 分流进各自的抖动缓冲，再解码混音。
    audioIo.submitRemoteFrame(frame.encode());

    _lastAudioAt[frame.senderId] = DateTime.now();
    if (!sender.isSpeaking) {
      sender.isSpeaking = true;
      _notifyMembers();
    }
  }

  /// 全双工模式下把已经停止送音频的成员的「正在说话」熄灭。
  ///
  /// 缺了这一步，WiFi 房里的说话指示灯一旦亮起就永远不会灭——
  /// 只有 PTT 帧会复位它，而全双工模式根本不发 PTT 帧。
  void _expireSpeakingStates() {
    // Peers choose their own transmit mode, so every receiver expires silence.

    final now = DateTime.now();
    var changed = false;

    for (final member in _members.values) {
      if (member.memberId == _selfMemberId) continue;
      if (!member.isSpeaking) continue;

      final last = _lastAudioAt[member.memberId];
      if (last == null || now.difference(last) > _speakingTimeout) {
        member.isSpeaking = false;
        changed = true;
      }
    }

    if (changed) _notifyMembers();
  }

  void _handleJoinReq(Frame frame) {
    if (!_isHost) return;
    final payload = JoinRequestPayload.decode(frame.payload);
    if (payload == null) return;

    // 重连判定：令牌相同才认定是「老成员回来了」。昵称谁都可以填一样的，
    // 不能作为身份依据——同昵称的新人应当拿到新的成员号。
    // 兼容兜底：旧版客户端的令牌是全零，对这类客户端退回昵称匹配，
    // 但仅当在册成员也是全零令牌时才生效（新客户端有唯一令牌，不受影响）。
    final joinToken = payload.sessionToken;
    int allocatedId = 0;
    if (!_isZeroToken(joinToken)) {
      for (final entry in _members.entries) {
        final existing = entry.value.sessionToken;
        if (existing != null &&
            !_isZeroToken(existing) &&
            _tokensEqual(existing, joinToken)) {
          allocatedId = entry.key;
          break;
        }
      }
    } else {
      for (final entry in _members.entries) {
        final existing = entry.value.sessionToken;
        if ((existing == null || _isZeroToken(existing)) &&
            entry.value.nickname == payload.nickname) {
          allocatedId = entry.key;
          break;
        }
      }
    }

    if (allocatedId == 0) {
      int newId = 2;
      while (_members.containsKey(newId) && newId <= 6) {
        newId++;
      }
      if (newId > 6) return; // Room is full (max 6)
      allocatedId = newId;
    }

    final existing = _members[allocatedId];
    _members[allocatedId] = Member(
      memberId: allocatedId,
      nickname: payload.nickname,
      sessionToken: payload.sessionToken,
      // 重连回来的老成员保留原有资历，不能因为断线重连就变成最年轻的。
      joinOrder: existing?.joinOrder ?? _nextJoinOrder++,
      endpoint: existing?.endpoint ?? '',
    );

    _recordMemberIdentity(allocatedId, payload.nickname);
    if (roomInvite != null) {
      sendFrame(
        Frame(
          type: FrameType.admission,
          senderId: 1,
          seq: _nextSeq(),
          payload: Uint8List.fromList([allocatedId, ...joinToken]),
        ),
      );
    }
    _broadcastRoster();
    _notifyMembers();
    _syncChatHistoryTo(allocatedId);
  }

  void _handleRoster(Frame frame) {
    final payload = RosterPayload.decode(frame.payload);
    if (payload == null) return;

    _members.clear();
    for (final rm in payload.members) {
      _recordMemberIdentity(rm.memberId, rm.nickname);
      _members[rm.memberId] = Member(
        memberId: rm.memberId,
        nickname: rm.nickname,
        isHost: rm.isHost,
        isMuted: rm.isMuted,
        isSpeaking: rm.isSpeaking,
      );
      if (roomInvite == null && rm.nickname == selfNickname && !isHost) {
        _selfMemberId = rm.memberId;
        transport?.updateSelfMemberId(_selfMemberId);
      }
    }

    if (roomInvite != null && !_members.containsKey(_selfMemberId)) return;
    final recovered = _state == RoomState.reconnecting;
    if (_state != RoomState.inRoom) {
      _updateState(RoomState.inRoom);
    }
    if (recovered) {
      final seconds = _reconnectController.elapsed.inSeconds;
      _reconnectController.cancel();
      AppLog.info('重连', '房间连接已恢复（耗时 ${seconds}s）');
    }

    // 名单换了以后，已经不在房里的人的音频流留着只会占内存。
    final gone =
        _lastAudioAt.keys.where((id) => !_members.containsKey(id)).toList();
    for (final id in gone) {
      _lastAudioAt.remove(id);
      audioIo.removeRemoteMember(id);
    }

    _notifyMembers();
  }

  void _handlePttState(Frame frame) {
    final payload = PttStatePayload.decode(frame.payload);
    if (payload == null) return;

    final member = _members[frame.senderId];
    if (member != null) {
      member.isSpeaking = payload.isPressed;
      _notifyMembers();
    }
  }

  void _handleHeartbeat(Frame frame) {
    final member = _members[frame.senderId];
    if (member != null) {
      member.lastActiveAt = DateTime.now();
    }
  }

  void _handleLeave(Frame frame) {
    _members.remove(frame.senderId);
    _lastAudioAt.remove(frame.senderId);
    audioIo.removeRemoteMember(frame.senderId);
    _notifyMembers();

    if (_isHost) {
      _broadcastRoster();
    }
  }

  /// 收到交接帧（0x07）：立刻执行迁移。
  Future<void> _handleHostHandover(Frame frame) async {
    final plan = _decodePlan(frame, '交接帧');
    if (plan == null) return;
    if (!_isPlanFresh(plan)) return;

    _cachedPlan = plan;
    await _runTransfer(plan);
  }

  /// 收到交接快照（0x08）：只缓存，不改变当前房主。
  ///
  /// 快照是房主定期广播的「万一我挂了，你们照这个迁」。真正触发迁移的是
  /// 交接帧或房主超时，所以这里绝不能动 isHost——否则一条迟到的快照
  /// 就能把现任房主顶下去。
  void _handleHostAnnounce(Frame frame) {
    if (_isHost) return;
    final plan = _decodePlan(frame, '交接快照');
    if (plan == null) return;
    if (!_isPlanFresh(plan)) return;

    _cachedPlan = plan;
  }

  HostTransferPlan? _decodePlan(Frame frame, String what) {
    try {
      return HostTransferCodec.decode(frame.payload);
    } catch (e) {
      AppLog.warn('RoomSession', '收到无法解析的$what，已忽略', e);
      return null;
    }
  }

  bool _isPlanFresh(HostTransferPlan plan) {
    final maxOrder = plan.members
        .map((m) => m.joinOrder)
        .reduce((a, b) => a > b ? a : b);
    if (maxOrder < _highestSeenJoinOrder) return false;
    _highestSeenJoinOrder = maxOrder;
    return true;
  }

  /// 房主超时后自动迁移。
  void checkHostFailover() {
    if (_isHost || _transferInProgress || _state != RoomState.inRoom) return;

    final currentHost = _members.values.cast<Member?>().firstWhere(
      (m) => m?.isHost == true,
      orElse: () => null,
    );

    // 如果刚进房间名单里还没标出房主，先等待名单帧，不误判失联
    if (currentHost == null) return;

    final now = DateTime.now();
    final hostAlive =
        now.difference(currentHost.lastActiveAt) < _hostSilenceBeforeReconnect;
    if (hostAlive) return;

    final plan = _cachedPlan;
    if (plan == null || transport?.supportsHostTransfer != true) {
      _beginReconnect('超过 ${_hostSilenceBeforeReconnect.inSeconds} 秒未收到房主数据');
      return;
    }

    AppLog.info('RoomSession', '房主已失联，按快照迁移到 ${plan.successor.nickname}');
    _transferInProgress = true;
    _runTransfer(plan).whenComplete(() => _transferInProgress = false);
  }

  Future<void> _runTransfer(HostTransferPlan plan) async {
    final t = transport;
    if (t == null || !t.supportsHostTransfer) {
      AppLog.error('RoomSession', '当前房型不支持房主转移');
      return;
    }
    if (plan.successorId == _selfMemberId) {
      await _becomeHost(plan, t);
    } else {
      await _followNewHost(plan, t);
    }
  }

  Future<void> _becomeHost(HostTransferPlan plan, RoomTransport t) async {
    final seed = HostTransferSeed.from(plan);
    _updateState(RoomState.reconnecting);

    if (!await t.becomeHost()) {
      AppLog.error('RoomSession', '接任房主失败：无法开始监听');
      _updateState(RoomState.disconnected);
      return;
    }

    // 交接后所有人的成员号都会变：继任者取 1，其余按 joinOrder 顺延。
    // 传输层必须跟着更新，否则语音会被转发到错的端点。
    _members.clear();
    _lastAudioAt.clear();
    for (final m in seed.members) {
      final id = m.newId + 1; // seed 里继任者是 0，房主统一用 1
      _members[id] = Member(
        memberId: id,
        nickname: m.nickname,
        joinOrder: m.joinOrder,
        endpoint: m.endpoint,
        isHost: id == 1,
      );
    }

    _selfMemberId = 1;
    _nextJoinOrder = seed.nextJoinOrder;
    _isHost = true;
    t.updateSelfMemberId(_selfMemberId);

    _updateState(RoomState.inRoom);
    _broadcastRoster();
    _notifyMembers();
    AppLog.info('RoomSession', '已接任房主，房内 ${_members.length} 人');
  }

  Future<void> _followNewHost(HostTransferPlan plan, RoomTransport t) async {
    _isHost = false;
    _updateState(RoomState.reconnecting);

    if (!await t.reconnectToHost(plan.successor.endpoint)) {
      AppLog.error('RoomSession', '重连新房主失败');
      _updateState(RoomState.disconnected);
      return;
    }

    // 成员号由新房主重新分配，所以重新走一次入房；音频管线不重启，
    // 否则会有一段可听见的断音。
    await joinRoom(startAudio: false);
    AppLog.info('RoomSession', '已跟随新房主 ${plan.successor.nickname} 重连');
  }

  /// 用当前成员表和传输层已知的端点组装一份交接计划。
  ///
  /// 端点未知的成员不能当继任者——别人找不到他。
  HostTransferPlan? _buildTransferPlan({int? preferredSuccessorId}) {
    final known = transport?.peerEndpoints ?? const <int, String>{};
    final candidates = <TransferCandidate>[];

    for (final m in _members.values) {
      if (m.memberId == _selfMemberId) continue; // 房主自己不是继任候选
      final endpoint = known[m.memberId] ?? m.endpoint;
      if (endpoint.trim().isEmpty) continue;
      m.endpoint = endpoint;
      candidates.add(
        TransferCandidate(
          memberId: m.memberId,
          joinOrder: m.joinOrder,
          nickname: m.nickname,
          endpoint: endpoint,
        ),
      );
    }

    if (candidates.isEmpty) return null;
    if (preferredSuccessorId == null) return HostElection.plan(candidates);

    if (!candidates.any((c) => c.memberId == preferredSuccessorId)) return null;
    try {
      return HostTransferPlan(
        successorId: preferredSuccessorId,
        members:
            candidates
                .map(
                  (c) => HostTransferMember(
                    memberId: c.memberId,
                    joinOrder: c.joinOrder,
                    nickname: c.nickname,
                    endpoint: c.endpoint,
                  ),
                )
                .toList(),
      );
    } catch (e) {
      AppLog.error('RoomSession', '交接计划校验未通过', e);
      return null;
    }
  }

  /// 房主定期广播交接快照，让每个人手里都有「房主没了该怎么办」的答案。
  Future<void> _broadcastSnapshot() async {
    if (!_isHost) return;
    if (transport?.supportsHostTransfer != true) return;

    final plan = _buildTransferPlan();
    if (plan == null) return;

    _cachedPlan = plan;
    await sendFrame(
      Frame(
        type: FrameType.hostAnnounce,
        senderId: _selfMemberId,
        seq: _nextSeq(),
        payload: HostTransferCodec.encode(plan),
      ),
    );
  }

  void _broadcastRoster() {
    if (!_isHost) return;

    // 名单变了，传输层的 UDP 白名单也要跟着变：端点注册只认在册成员号。
    _syncKnownMembersToTransport();

    final rosterMembers =
        _members.values.map((m) {
          int flags = 0;
          if (m.isHost) flags |= 0x01;
          if (m.isMuted) flags |= 0x02;
          if (m.isSpeaking) flags |= 0x04;
          return RosterMember(
            memberId: m.memberId,
            flags: flags,
            nickname: m.nickname,
          );
        }).toList();

    final payload = RosterPayload(
      hostId: _selfMemberId,
      members: rosterMembers,
    );
    final frame = Frame(
      type: FrameType.roster,
      senderId: _selfMemberId,
      seq: _nextSeq(),
      payload: payload.encode(),
    );
    sendFrame(frame);
  }

  /// 把在册成员号同步给传输层。房主侧的 UDP 端点注册与转发只认这份
  /// 白名单——不在册的 senderId 一律在传输层丢弃，否则局域网内任何
  /// 设备都能用伪造的成员号抢先登记语音端点、借房主转发垃圾帧。
  void _syncKnownMembersToTransport() {
    transport?.updateKnownMemberIds(_members.keys.toSet());
  }

  Future<void> _startAudioPipeline() async {
    // 重连会再次走到这里。不先停掉上一轮的采集，回调会叠加成两份，
    // 每帧音频都会被发送两遍。
    await audioIo.stopCapture();
    await audioIo.clearRemoteMembers();
    if (!_audioStarted || _closed) return;

    await audioIo.startCapture((opusPacket, level) {
      if (_closed || !_audioStarted || _state != RoomState.inRoom || isMuted) {
        _voiceGate.reset();
        return;
      }
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final packets =
          isFullDuplex
              ? _voiceGate.process(opusPacket, level, nowMs)
              : (isPttPressed ? [opusPacket] : <Uint8List>[]);
      if (!_waveController.isClosed && nowMs - _lastWaveUiEmitMs >= 33) {
        _lastWaveUiEmitMs = nowMs;
        _waveController.add(packets.isEmpty ? 0 : level);
      }
      for (final packet in packets) {
        sendFrame(
          Frame(
            type: FrameType.audio,
            senderId: _selfMemberId,
            seq: _nextSeq(),
            payload: packet,
          ),
        );
      }
    }, bitrateBps: isBluetooth ? _bluetoothBitrate : _wifiBitrate);
    if (!_audioStarted || _closed) {
      await audioIo.stopCapture();
      await audioIo.stopPlayback();
      return;
    }

    // 播放不再需要 Dart 定时器：抖动缓冲、解码、混音、送扬声器全在原生侧，
    // 由 AudioTrack 的写阻塞天然定速（原来的 Timer.periodic(20ms) 有调度漂移）。
    // 这里只剩「谁还在说话」的超时判定，100ms 一次足够。
    _speakingWatchTimer?.cancel();
    _speakingWatchTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _expireSpeakingStates(),
    );
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final frame = Frame(
        type: FrameType.heartbeat,
        senderId: _selfMemberId,
        seq: _nextSeq(),
        payload: Uint8List(0),
      );
      sendFrame(frame);

      // 房主定期广播交接快照、清理失联成员；成员则检查房主是不是已经失联。
      // 快照广播这步之前被漏掉了，导致房主掉线后没有任何人接管。
      if (_isHost) {
        pruneStaleMembers();
        _broadcastSnapshot();
      } else {
        checkHostFailover();
      }
    });
  }

  /// 房主清理超过 10 分钟没有合法帧的成员。恢复期内名额会保留，
  /// 重连时使用 sessionToken 认领原成员号和加入顺序。
  ///
  /// 公开而非私有：心跳定时器周期调用，测试与诊断工具也需要手动触发。
  void pruneStaleMembers() {
    final now = DateTime.now();
    final stale =
        _members.values
            .where(
              (m) =>
                  m.memberId != _selfMemberId &&
                  now.difference(m.lastActiveAt) > _memberTimeout,
            )
            .map((m) => m.memberId)
            .toList();
    if (stale.isEmpty) return;

    for (final id in stale) {
      final member = _members.remove(id);
      AppLog.info('RoomSession', '成员 #$id「${member?.nickname}」心跳超时，已从名单移除');
      _lastAudioAt.remove(id);
      audioIo.removeRemoteMember(id);
    }
    _notifyMembers();
    _broadcastRoster();
  }

  /// PTT 按住/松开切换。
  void setPtt(bool isPressed) {
    if (isPressed &&
        (isFullDuplex || isMuted || _closed || _state != RoomState.inRoom)) {
      return;
    }
    isPttPressed = isPressed;
    _notifyControls();
    final self = _members[_selfMemberId];
    if (self != null) {
      self.isSpeaking = isPressed;
      _notifyMembers();
    }

    final payload = PttStatePayload(isPressed: isPressed);
    final frame = Frame(
      type: FrameType.pttState,
      senderId: _selfMemberId,
      seq: _nextSeq(),
      payload: payload.encode(),
    );
    sendFrame(frame);
  }

  void toggleMute() {
    final nextMuted = !audioIo.isMuted;
    audioIo.setMuted(nextMuted);
    if (nextMuted) {
      setPtt(false);
      _voiceGate.reset();
    }
    _notifyControls();
    final self = _members[_selfMemberId];
    if (self != null) {
      self.isMuted = nextMuted;
      _notifyMembers();
    }
  }

  void setSpeakerphone(bool enabled) {
    audioIo.setSpeakerphone(enabled);
  }

  Future<bool> _attemptReconnect() async {
    if (_closed || _isHost) return false;
    final reconnect = _reconnectTransport;
    if (reconnect == null) return false;
    _updateState(RoomState.reconnecting);
    AppLog.info(
      '重连',
      '第 ${_reconnectController.retryCount} 次尝试恢复链路，剩余 ${_reconnectController.remaining.inMinutes} 分钟',
    );
    if (!await reconnect()) return false;
    if (_closed) return false;

    // 物理链路恢复后重新 PAKE，避免沿用旧连接上的握手状态。房主仍持有
    // 同一个随机房间密钥，sessionToken 则让重连成员取回原来的身份。
    secureCodec = null;
    _admitted = false;
    _selfMemberId = 0;
    _members.clear();
    _lastAudioAt.clear();
    await audioIo.clearRemoteMembers();
    _updateState(RoomState.reconnecting);

    final joined = stateStream
        .firstWhere((value) => value == RoomState.inRoom)
        .timeout(const Duration(seconds: 8));
    if (_admission != null) {
      _admission!.startClient();
    } else {
      await _sendJoinRequest();
    }
    _startHeartbeat();
    try {
      await joined;
      return true;
    } on TimeoutException {
      AppLog.warn('重连', '链路已恢复，但 8 秒内未重新通过入房验证');
      return false;
    }
  }

  void triggerDisconnect() {
    _beginReconnect('手动触发链路恢复');
  }

  void _handleTransportDisconnection(TransportDisconnection event) {
    _beginReconnect(
      '底层链路断开：${event.reason}${event.detail == null ? '' : ' (${event.detail})'}',
    );
  }

  void _beginReconnect(String reason) {
    if (_closed || _isHost || _state == RoomState.idle) return;
    if (_reconnectTransport == null) {
      AppLog.error('重连', '$reason；当前传输层没有恢复入口');
      _updateState(RoomState.disconnected);
      return;
    }
    if (_reconnectController.isReconnecting) return;
    isPttPressed = false;
    _voiceGate.reset();
    _notifyControls();
    unawaited(audioIo.clearRemoteMembers());
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _updateState(RoomState.reconnecting);
    AppLog.warn('重连', '$reason；将在 10 分钟内自动恢复');
    _reconnectController.start();
  }

  Future<void> _finishReconnectWindow() async {
    if (_closed || _isHost) return;
    AppLog.error('重连', '自动恢复已持续 10 分钟，房间连接未能恢复');
    _audioStarted = false;
    isPttPressed = false;
    _voiceGate.reset();
    await _backgroundControls?.close();
    _backgroundControls = null;
    await audioIo.stopCapture();
    await audioIo.stopPlayback();
    await audioIo.clearRemoteMembers();
    await transport?.stop();
    _updateState(RoomState.disconnected);
  }

  /// Hook for network transmission
  void Function(Frame frame)? onSendFrame;

  Future<void> sendFrame(Frame frame) {
    if (_closed || (roomInvite != null && secureCodec == null)) {
      return Future.value();
    }
    if (secureCodec == null) return _sendFrame(frame);
    if (_pendingOutgoing >= 256) return Future.value();
    _pendingOutgoing++;
    final next = _outgoingQueue
        .then((_) async {
          if (!_closed) await _sendFrame(frame);
        })
        .whenComplete(() => _pendingOutgoing--);
    _outgoingQueue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _sendFrame(Frame frame) async {
    Frame outFrame = frame;
    if (secureCodec != null) {
      try {
        outFrame = await secureCodec!.seal(frame);
      } catch (e) {
        AppLog.error('RoomSession', '密封加密帧失败，已放弃发送', e);
        return;
      }
    }
    onSendFrame?.call(outFrame);
  }

  /// 房主主动把房主身份转移给目标成员。
  Future<void> transferHost(int targetMemberId) async {
    if (!_isHost) return;

    final t = transport;
    if (t == null || !t.supportsHostTransfer) {
      AppLog.error('RoomSession', '当前房型不支持房主转移');
      return;
    }

    final target = _members[targetMemberId];
    if (target == null) return;

    final plan = _buildTransferPlan(preferredSuccessorId: targetMemberId);
    if (plan == null) {
      AppLog.error('RoomSession', '还不知道「${target.nickname}」的连接地址，等对方说过话后再试');
      return;
    }

    await sendFrame(
      Frame(
        type: FrameType.hostHandover,
        senderId: _selfMemberId,
        seq: _nextSeq(),
        payload: HostTransferCodec.encode(plan),
      ),
    );
    AppLog.info('RoomSession', '把房主转移给「${target.nickname}」');

    // 留一点时间让交接帧真的发出去，再自己降为普通成员重连过去。
    await Future.delayed(const Duration(milliseconds: 300));
    _transferInProgress = true;
    try {
      await _followNewHost(plan, t);
    } finally {
      _transferInProgress = false;
    }
  }

  bool get useBuiltinMic => audioIo.useBuiltinMic;

  void setUseBuiltinMic(bool useBuiltin) {
    audioIo.setUseBuiltinMic(useBuiltin);
    _notifyControls();
  }

  /// 将未读数重置归零（面板打开或用户浏览时调用）
  void markChatRead() {
    if (_unreadChatCount != 0) {
      _unreadChatCount = 0;
      if (!_unreadStreamController.isClosed) {
        _unreadStreamController.add(0);
      }
    }
  }

  /// 发送一条文字消息
  Future<void> sendChat(String text) async {
    if (_state != RoomState.inRoom) {
      throw StateError('Cannot send chat message when not in room.');
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError(
        'Chat message text cannot be empty or whitespace-only.',
      );
    }

    if (utf8.encode(trimmed).length > maxChatTextBytes) {
      throw ArgumentError('消息最多 $maxChatTextBytes UTF-8 字节。');
    }
    final fullNickname = _members[_selfMemberId]?.nickname ?? selfNickname;
    final rawCode = DeviceCode.split(fullNickname).$2 ?? DeviceCode.current;
    final code = DeviceCode.toNumeric(rawCode);
    final now = DateTime.now();
    final timestampMs = now.millisecondsSinceEpoch;
    final seq = _nextSeq();
    final messageId = '${code}_${timestampMs}_$seq';

    // ChatMessagePayload 会校验 480 字节 UTF-8 上限，超长直接抛出 ArgumentError
    final payload = ChatMessagePayload(
      text: trimmed,
      timestampMs: timestampMs,
      senderCode: code,
    );
    final payloadBytes = payload.encode();

    final frame = Frame(
      type: FrameType.chat,
      senderId: _selfMemberId,
      seq: seq,
      payload: payloadBytes,
    );

    // 记录本机发送键值，防止因广播回送导致重复追加
    _markChatKeySeen(_selfMemberId, seq);

    // 经由标准 sendFrame 发送（若配置了 secureCodec 将自动加密为 sealed 帧）
    await sendFrame(frame);

    // 本地立即追加一条 isLocal = true 消息
    _recordMemberIdentity(_selfMemberId, fullNickname);
    final cleanNickname =
        _currentNicknameByCode[code] ?? DeviceCode.split(fullNickname).$1;
    final prevNick = _previousNicknamesByCode[code]?.join('、');

    final localMsg = ChatMessage(
      messageId: messageId,
      senderId: _selfMemberId,
      senderCode: code,
      senderNickname: cleanNickname,
      previousNickname: prevNick,
      seq: seq,
      text: trimmed,
      timestamp: now,
      isLocal: true,
      isHost: _isHost,
    );
    _appendChatMessage(localMsg, isIncoming: false);
  }

  void _handleChatFrame(Frame frame) {
    if (_state != RoomState.inRoom) return;

    // 1. 过滤本机回送帧
    if (frame.senderId == _selfMemberId) return;

    // 2. 过滤未在册成员的帧
    final sender = _members[frame.senderId];
    if (sender == null) {
      AppLog.warn('RoomSession', '收到未在册成员 #${frame.senderId} 的聊天帧，已忽略');
      return;
    }

    // 3. 有界去重检查 (senderId, seq)
    if (_isChatKeySeen(frame.senderId, frame.seq)) {
      return;
    }
    _markChatKeySeen(frame.senderId, frame.seq);

    // 4. 解码 Payload
    final payload = ChatMessagePayload.decode(frame.payload);
    if (payload == null) {
      AppLog.warn('RoomSession', '来自成员 #${frame.senderId} 的聊天帧载荷格式损坏，已忽略');
      return;
    }

    // 5. 身份与曾用名关联
    _recordMemberIdentity(frame.senderId, sender.nickname);
    final split = DeviceCode.split(sender.nickname);
    final senderCode =
        (payload.senderCode != '0000' && payload.senderCode.isNotEmpty)
            ? DeviceCode.toNumeric(payload.senderCode)
            : (split.$2 ?? 'M${frame.senderId}');
    final cleanNickname = _currentNicknameByCode[senderCode] ?? split.$1;
    final prevNick = _previousNicknamesByCode[senderCode]?.join('、');

    final timestamp =
        payload.timestampMs != 0
            ? DateTime.fromMillisecondsSinceEpoch(payload.timestampMs)
            : DateTime.now();
    final messageId =
        '${senderCode}_${timestamp.millisecondsSinceEpoch}_${frame.seq}';

    // 6. 组装并追加消息
    final msg = ChatMessage(
      messageId: messageId,
      senderId: frame.senderId,
      senderCode: senderCode,
      senderNickname: cleanNickname,
      previousNickname: prevNick,
      seq: frame.seq,
      text: payload.text,
      timestamp: timestamp,
      isLocal: false,
      isHost: sender.isHost,
    );
    _appendChatMessage(msg, isIncoming: true);
  }

  /// 房主向新加入成员同步现存的历史聊天记录
  void _syncChatHistoryTo(int targetMemberId) {
    if (!_isHost) return;
    for (final msg in _chatMessages) {
      if (msg.isRecalled) continue;
      final syncPayload = ChatSyncPayload(
        targetMemberId: targetMemberId,
        senderId: msg.senderId,
        senderCode: msg.senderCode,
        timestampMs: msg.timestamp.millisecondsSinceEpoch,
        messageId: msg.messageId,
        nickname: msg.senderNickname,
        text: msg.text,
      );
      final frame = Frame(
        type: FrameType.chatSync,
        senderId: _selfMemberId,
        seq: _nextSeq(),
        payload: syncPayload.encode(),
      );
      sendFrame(frame);
    }
  }

  void _handleChatSyncFrame(Frame frame) {
    if (_state != RoomState.inRoom && _state != RoomState.connecting) return;
    final payload = ChatSyncPayload.decode(frame.payload);
    if (payload == null) return;

    // 历史同步是房主的特权帧：payload 里的 senderId/senderCode 都是自报的，
    // 不校验实际发送者的话，任何成员都能伪造「历史消息」冒充他人发言。
    final sender = _members[frame.senderId];
    if (sender == null || !sender.isHost) {
      AppLog.warn('RoomSession', '拒绝来自非房主 #${frame.senderId} 的历史同步帧');
      return;
    }

    // 仅接收定向发给本机或广播的历史同步帧
    if (payload.targetMemberId != 0 &&
        payload.targetMemberId != _selfMemberId) {
      return;
    }

    // 根据 messageId 去重，防止重复同步
    if (_chatMessages.any((m) => m.messageId == payload.messageId)) {
      return;
    }

    _recordMemberIdentity(payload.senderId, payload.nickname);
    final cleanNick =
        _currentNicknameByCode[payload.senderCode] ?? payload.nickname;
    final prevNick = _previousNicknamesByCode[payload.senderCode]?.join('、');

    final msg = ChatMessage(
      messageId: payload.messageId,
      senderId: payload.senderId,
      senderCode: payload.senderCode,
      senderNickname: cleanNick,
      previousNickname: prevNick,
      seq: 0,
      text: payload.text,
      timestamp: DateTime.fromMillisecondsSinceEpoch(payload.timestampMs),
      isLocal: payload.senderCode == DeviceCode.current,
      isHost: payload.senderId == 1,
    );

    _chatMessages.add(msg);
    _chatMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (_chatMessages.length > maxChatHistory) {
      _chatMessages.removeAt(0);
    }
    if (!_chatStreamController.isClosed) {
      _chatStreamController.add(msg);
    }
    if (!_chatListController.isClosed) {
      _chatListController.add(List.unmodifiable(_chatMessages));
    }
  }

  /// 撤回 / 为所有人删除自己发送的消息
  Future<void> recallMessage(String messageId) async {
    final idx = _chatMessages.indexWhere((m) => m.messageId == messageId);
    if (idx == -1) return;
    final target = _chatMessages[idx];

    final myCode = DeviceCode.toNumeric(
      DeviceCode.split(selfNickname).$2 ?? DeviceCode.current,
    );
    // 权限校验：只能删除自己发送的消息
    if (!target.isLocal && DeviceCode.toNumeric(target.senderCode) != myCode) {
      throw StateError('Cannot delete messages sent by other members.');
    }

    // 本地移除
    _chatMessages.removeAt(idx);
    if (!_chatListController.isClosed) {
      _chatListController.add(List.unmodifiable(_chatMessages));
    }

    // 广播撤回帧给所有人
    final deletePayload = ChatDeletePayload(
      senderCode: myCode,
      messageId: messageId,
    );
    final frame = Frame(
      type: FrameType.chatDelete,
      senderId: _selfMemberId,
      seq: _nextSeq(),
      payload: deletePayload.encode(),
    );
    await sendFrame(frame);
  }

  void _handleChatDeleteFrame(Frame frame) {
    final payload = ChatDeletePayload.decode(frame.payload);
    if (payload == null) return;

    final idx = _chatMessages.indexWhere(
      (m) => m.messageId == payload.messageId,
    );
    if (idx == -1) return;

    final target = _chatMessages[idx];
    // 权限校验：只比对 payload 里的 senderCode 不够——设备码在聊天界面
    // 可见且仅 3 位数字，任何成员都能冒填。改为取「帧的实际发送者」在
    // 名单里的设备码与消息作者比对，冒用他人短码的撤回请求一律无效。
    final sender = _members[frame.senderId];
    if (sender == null) {
      AppLog.warn('RoomSession', '收到不在册成员 #${frame.senderId} 的撤回请求，已忽略');
      return;
    }
    final senderCode = DeviceCode.toNumeric(
      DeviceCode.split(sender.nickname).$2 ?? 'M${frame.senderId}',
    );
    if (senderCode != DeviceCode.toNumeric(target.senderCode)) {
      AppLog.warn(
        'RoomSession',
        '收到非法撤回请求：发起方 #${frame.senderId}（$senderCode）试图撤回 ${target.senderCode} 的消息',
      );
      return;
    }

    _chatMessages.removeAt(idx);
    if (!_chatListController.isClosed) {
      _chatListController.add(List.unmodifiable(_chatMessages));
    }
  }

  void _recordMemberIdentity(int memberId, String fullNickname) {
    final split = DeviceCode.split(fullNickname);
    final cleanNick = split.$1;
    final code = split.$2 ?? 'M$memberId';

    if (_currentNicknameByCode.containsKey(code)) {
      final oldNick = _currentNicknameByCode[code]!;
      if (oldNick != cleanNick) {
        _previousNicknamesByCode
            .putIfAbsent(code, () => <String>{})
            .add(oldNick);
        _currentNicknameByCode[code] = cleanNick;
        // 同步更新之前该成员发出的历史消息
        bool changed = false;
        for (int i = 0; i < _chatMessages.length; i++) {
          if (_chatMessages[i].senderCode == code) {
            _chatMessages[i] = _chatMessages[i].copyWith(
              senderNickname: cleanNick,
              previousNickname: _previousNicknamesByCode[code]?.join('、'),
            );
            changed = true;
          }
        }
        if (changed && !_chatListController.isClosed) {
          _chatListController.add(List.unmodifiable(_chatMessages));
        }
      }
    } else {
      _currentNicknameByCode[code] = cleanNick;
    }
  }

  bool _isChatKeySeen(int senderId, int seq) =>
      _seenChatKeys.contains('$senderId:$seq');

  void _markChatKeySeen(int senderId, int seq) {
    final key = '$senderId:$seq';
    if (_seenChatKeys.add(key)) {
      _seenChatKeyOrder.add(key);
      if (_seenChatKeyOrder.length > maxDeduplicationKeys) {
        final oldest = _seenChatKeyOrder.removeAt(0);
        _seenChatKeys.remove(oldest);
      }
    }
  }

  void _appendChatMessage(ChatMessage msg, {required bool isIncoming}) {
    _chatMessages.add(msg);
    if (_chatMessages.length > maxChatHistory) {
      _chatMessages.removeAt(0);
    }
    if (!_chatStreamController.isClosed) {
      _chatStreamController.add(msg);
    }
    if (!_chatListController.isClosed) {
      _chatListController.add(List.unmodifiable(_chatMessages));
    }
    if (isIncoming) {
      _unreadChatCount++;
      if (!_unreadStreamController.isClosed) {
        _unreadStreamController.add(_unreadChatCount);
      }
    }
  }

  Future<void> leave() async {
    _audioStarted = false;
    isPttPressed = false;
    _voiceGate.reset();
    await _backgroundControls?.close();
    _backgroundControls = null;
    final leavePayload = LeavePayload();
    final frame = Frame(
      type: FrameType.leave,
      senderId: _selfMemberId,
      seq: _nextSeq(),
      payload: leavePayload.encode(),
    );
    // 离房帧必须先落到对端再拆传输层：sendFrame 只是把字节挂上 socket
    // 的发送缓冲，下面的 stop() 会销毁链路、连缓冲一起丢弃。flush 是
    // I/O 完成事件，不用定时器——定时器等待在测试的 FakeAsync 时区里
    // 会永远挂起。
    await sendFrame(frame);
    await transport?.flush();

    _speakingWatchTimer?.cancel();
    _speakingWatchTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _audioStarted = false;
    _reconnectController.cancel();
    await _transportDisconnectSubscription?.cancel();
    _transportDisconnectSubscription = null;
    await _transportIncomingSubscription?.cancel();
    _transportIncomingSubscription = null;
    _reconnectTransport = null;

    await audioIo.stopCapture();
    await audioIo.stopPlayback();
    await audioIo.clearRemoteMembers();
    await transport?.stop();
    _closed = true;
    _admission?.close();
    _admission = null;
    secureCodec = null;
    roomInvite = null;

    _members.clear();
    _lastAudioAt.clear();
    _cachedPlan = null;
    _highestSeenJoinOrder = 0;
    _transferInProgress = false;
    _nextJoinOrder = 1;

    // 清空聊天状态
    _chatMessages.clear();
    _unreadChatCount = 0;
    _seenChatKeys.clear();
    _seenChatKeyOrder.clear();
    if (!_chatListController.isClosed) {
      _chatListController.add(const []);
    }
    if (!_unreadStreamController.isClosed) {
      _unreadStreamController.add(0);
    }

    _updateState(RoomState.idle);
    _notifyMembers();
  }

  int _nextSeq() {
    _seq = (_seq + 1) & 0xFFFF;
    return _seq;
  }

  void _updateState(RoomState newState) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  }

  void _notifyMembers() {
    if (!_membersController.isClosed) {
      _membersController.add(_members.values.toList());
    }
  }

  /// 必须 await。
  ///
  /// 原来是同步调用 `leave()` 之后立刻 close 三个 controller：`leave()` 跑到
  /// 第一个 await（stopCapture）就挂起了，等它恢复执行时再去 `_updateState`
  /// 和 `_notifyMembers`，写的已经是关掉的 controller，直接抛 StateError。
  Future<void>? _disposeFuture;

  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    await leave();
    await transport?.dispose();
    await _controlsController.close();
    transport = null;
    _chatMessages.clear();
    _seenChatKeys.clear();
    _seenChatKeyOrder.clear();
    await _chatStreamController.close();
    await _chatListController.close();
    await _unreadStreamController.close();
    await _stateController.close();
    await _membersController.close();
    await _waveController.close();
  }
}
