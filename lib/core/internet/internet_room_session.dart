// ignore_for_file: experimental_member_use

import 'dart:async';

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';

import '../audio/noise_reduction.dart';
import '../diagnostics/app_log.dart';
import '../platform/background_call_controls.dart';
import '../protocol/payloads/chat_image.dart';
import '../security/room_invite.dart';
import '../security/session_crypto.dart';
import '../security/spake2.dart';
import '../session/room_session.dart' show VoiceMode;
import 'internet_audio_profile.dart';
import 'internet_invite_credentials.dart';
import 'internet_models.dart';
import 'presence_announcements.dart';
import 'internet_room_api.dart';
import 'server_profile_store.dart';
import 'internet_features.dart';
import 'hybrid_audio.dart';

enum InternetConnectionState {
  connecting,
  connected,
  reconnecting,
  disconnected,
}

class InternetChatMessage {
  const InternetChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.sentAt,
    required this.isMine,
    this.imageBytes,
    this.imageMimeType,
    this.imageName,
  });
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime sentAt;
  final bool isMine;
  final Uint8List? imageBytes;
  final String? imageMimeType;
  final String? imageName;

  bool get hasImage => imageBytes != null;
}

class InternetRoomSession extends ChangeNotifier {
  InternetRoomSession._({
    required this.api,
    required this.profile,
    // Keep call sites readable as `nickname:` rather than exposing storage.
    required String nickname,
    required this.roomId,
    required this.memberId,
    required this.resumeToken,
    required this.isHost,
    required this._inviteCode,
    required this._roomKey,
    required this._audioProfile,
    required this._meteredNetwork,
    // ignore: prefer_initializing_formals
  }) : _nickname = nickname;

  @visibleForTesting
  InternetRoomSession.forTesting({
    required this.api,
    required this.profile,
    // Public test factory mirrors the production constructor's named API.
    required String nickname,
    required this.roomId,
    required this.memberId,
    required InternetRoomSummary summary,
    this.isHost = false,
    Future<void> Function(bool enabled)? microphoneForTesting,
    Future<void> Function(String kind, String name)? presenceForTesting,
    VoidCallback? mediaReadyForTesting,
    Future<void> Function()? audioRecoveryForTesting,
    Future<void> Function(bool, String?)? hybridActiveForTesting,
    // ignore: prefer_initializing_formals
  }) : _nickname = nickname,
       resumeToken = 'test-resume-token',
       _inviteCode = '1234',
       _roomKey = Uint8List(32),
       _audioProfile = InternetAudioProfile.clarity,
       _meteredNetwork = false,
       // Public test seam keeps the named argument accessible across libraries.
       // ignore: prefer_initializing_formals
       _microphoneForTesting = microphoneForTesting {
    _presenceForTesting = presenceForTesting;
    _mediaReadyForTesting = mediaReadyForTesting;
    _audioRecoveryForTesting = audioRecoveryForTesting;
    _hybridActiveForTesting = hybridActiveForTesting;
    _summary = summary;
    _connectionState = InternetConnectionState.connected;
  }

  final InternetRoomApi api;
  final ServerProfile profile;
  String _nickname;
  String get nickname => _nickname;
  final String roomId;
  final String memberId;
  String resumeToken;
  bool isHost;
  final String _inviteCode;
  final Uint8List _roomKey;
  final BackgroundCallControls _backgroundControls = BackgroundCallControls(
    Object(),
  );
  Future<void> Function(bool enabled)? _microphoneForTesting;

  Room? _livekitRoom;
  HybridAudio? _hybrid;
  Future<void> Function(bool, String?)? _hybridActiveForTesting;
  @visibleForTesting
  Future<void> refreshFeaturesForTesting() => _refreshFeatures();
  InternetFeatures features = const InternetFeatures();
  Timer? _featuresTimer;
  Future<void>? _hybridQueue;
  bool get hybridEnabled => _summary?.hybridAudioEnabled ?? false;
  bool get hybridAvailable =>
      features.hybridAudio && (_summary?.hybridAudioSupported ?? false);
  String? _hybridHostId;
  String? _activeHybridHostId;
  DateTime? _hybridRetryAfter;

  Future<void> setHybridEnabled(bool enabled) async {
    if (!isHost || !summary.hybridAudioSupported) {
      throw StateError('只有房主可以修改双线融合');
    }
    final updated = await api.setHybridAudio(roomId, enabled, resumeToken);
    if (_closed || _roomEnded) return;
    _summary = updated;
    _hybridRetryAfter = null;
    await _reconcileHybrid();
    notifyListeners();
  }

  Future<void> _reconcileHybrid() async {
    final hostId = _hybridHostId ?? (isHost ? memberId : null);
    final shouldEnable =
        hybridAvailable &&
        hybridEnabled &&
        hostId != null &&
        !_closed &&
        !_roomEnded &&
        !_managementRecovering &&
        _connectionState == InternetConnectionState.connected &&
        (_hybridRetryAfter == null ||
            DateTime.now().isAfter(_hybridRetryAfter!));
    if (_hybrid != null && _activeHybridHostId != hostId) {
      await _setHybridActive(false);
    }
    await _setHybridActive(shouldEnable);
  }

  int get directAudioCount => _hybrid?.directCount ?? 0;
  String get hybridStatus {
    if (!hybridEnabled) return '双线融合已关闭';
    if (!hybridAvailable) return '服务端已暂停融合，使用公网';
    if (_managementRecovering ||
        _connectionState != InternetConnectionState.connected) {
      return '等待公网恢复后自动连接直连';
    }
    if (_hybridRetryAfter != null &&
        DateTime.now().isBefore(_hybridRetryAfter!)) {
      return '公网通话中，稍后自动重试直连';
    }
    return _hybrid?.status ?? '正在准备直连，公网通话中';
  }

  Future<void> _refreshFeatures() async {
    try {
      final info = await api.info();
      if (_closed) return;
      features = info.features;
      await _reconcileHybrid();
      _hybrid?.features = features;
      notifyListeners();
    } catch (error) {
      AppLog.warn('DawnInternet', '动态功能配置刷新失败，保留上次配置：$error');
    }
  }

  Future<void> _setHybridActive(bool enabled) {
    final test = _hybridActiveForTesting;
    if (test != null) return test(enabled, _hybridHostId);
    if (!enabled && _hybrid == null && _hybridQueue == null) {
      return Future<void>.value();
    }
    final task = (_hybridQueue ?? Future<void>.value()).then((_) async {
      if (!enabled) {
        final previous = _hybrid;
        _hybrid = null;
        await previous?.close();
      } else if (_hybrid == null &&
          hybridEnabled &&
          !_managementRecovering &&
          features.hybridAudio &&
          !_closed &&
          !_roomEnded &&
          _connectionState == InternetConnectionState.connected &&
          _livekitRoom != null) {
        final hybrid = HybridAudio(
          selfId: memberId,
          room: _livekitRoom!,
          signal: _sendHybridSignal,
          canReceive: (id) =>
              !_managementRecovering &&
              (_managementMembers[id]?.canSpeak ?? false),
          changed: () {
            if (!_closed) notifyListeners();
          },
          features: features,
        );
        _hybrid = hybrid;
        _activeHybridHostId = _hybridHostId ?? memberId;
        try {
          await hybrid.start(hostId: _activeHybridHostId!, roomKey: _roomKey);
          await _syncMicrophone();
        } catch (error) {
          _hybrid = null;
          _hybridRetryAfter = DateTime.now().add(const Duration(seconds: 60));
          AppLog.warn('Hybrid', '直连启动失败，继续使用公网并稍后重试：$error');
          await hybrid.close();
        }
      }
      if (!_closed) notifyListeners();
    });
    late final Future<void> settled;
    settled = task.then(
      (_) {
        if (identical(_hybridQueue, settled)) _hybridQueue = null;
      },
      onError: (Object error, StackTrace _) {
        if (identical(_hybridQueue, settled)) _hybridQueue = null;
        AppLog.warn('Hybrid', '切换融合模式失败：$error');
      },
    );
    _hybridQueue = settled;
    return settled;
  }

  Future<void> _sendHybridSignal(String? to, Map<String, dynamic> data) async {
    final cipher = _chatCipher;
    final participant = _livekitRoom?.localParticipant;
    if (cipher == null || participant == null || _closed) return;
    const topic = 'dawnmesh.hybrid.v1';
    final packet = await cipher.encrypt(
      Uint8List.fromList(utf8.encode(jsonEncode(data))),
      associatedData: Uint8List.fromList(utf8.encode('$topic\u0000$memberId')),
    );
    await participant.publishData(
      [...packet.nonce, ...packet.ciphertext],
      reliable: true,
      topic: topic,
      destinationIdentities: to == null ? null : [to],
    );
  }

  Future<void> _receiveHybridSignal(DataReceivedEvent event) async {
    try {
      final from = event.participant?.identity;
      final cipher = _chatCipher;
      if (_hybrid == null ||
          from == null ||
          cipher == null ||
          event.data.length < 29 ||
          event.data.length > 15000) {
        return;
      }
      final clear = await cipher.decrypt(
        EncryptedPacket(
          nonce: Uint8List.fromList(event.data.sublist(0, 12)),
          ciphertext: Uint8List.fromList(event.data.sublist(12)),
        ),
        associatedData: Uint8List.fromList(
          utf8.encode('dawnmesh.hybrid.v1\u0000$from'),
        ),
      );
      _hybrid?.receive(
        from,
        jsonDecode(utf8.decode(clear)) as Map<String, dynamic>,
      );
    } catch (error) {
      AppLog.warn('Hybrid', '忽略无效直连信令：$error');
    }
  }

  Set<String>? _mediaMembersForTesting;
  bool _mediaConnectedForTesting = true;

  @visibleForTesting
  void receiveMediaRosterForTesting(Set<String> ids, {bool connected = true}) {
    _mediaMembersForTesting = ids;
    _mediaConnectedForTesting = connected;
    _setConnectionState(
      connected
          ? InternetConnectionState.connected
          : InternetConnectionState.reconnecting,
    );
    _refreshMembers();
  }

  EventsListener<RoomEvent>? _listener;
  WebSocket? _eventsSocket;
  StreamSubscription<dynamic>? _eventSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _eventReconnectTimer;
  Future<InternetConnectionGrant>? _resumeFuture;
  DateTime? _reconnectStartedAt;
  DateTime? _eventReconnectStartedAt;
  bool _mediaReconnectPending = false;
  bool _noiseReductionAttached = false;
  static const _audioChannel = MethodChannel('dev.dawnmesh.intercom/audio');
  Future<void>? _microphoneQueue;
  bool _audioRecoveryPending = false;
  Future<void> Function()? _audioRecoveryForTesting;
  Future<void> recoverAudioRoute() async {
    if (_closed || _roomEnded) return;
    _audioRecoveryPending = true;
    await _syncMicrophone();
  }

  bool _closed = false;
  bool _roomEnded = false;
  bool sessionReplaced = false;
  bool get hasTextMessages =>
      _messages.any((m) => !m.hasImage && m.text.trim().isNotEmpty);
  Future<void>? _roomEndTask;
  bool _muted = false;
  bool _policyCanSpeak = true;
  bool _mediaCanPublish = true;
  Timer? _mediaPermissionTimer;
  VoidCallback? _mediaReadyForTesting;
  bool _pttPressed = false;
  bool _speakerOn = true;
  InternetAudioProfile _audioProfile;
  bool _meteredNetwork;
  bool _audioProfileManuallySelected = false;
  VoiceMode _voiceMode = VoiceMode.pushToTalk;
  InternetConnectionState _connectionState = InternetConnectionState.connecting;
  InternetRoomSummary? _summary;
  final List<InternetMember> _members = [];
  final Map<String, InternetMember> _managementMembers = {};
  bool _hasManagementRoster = false;
  bool _managementRecovering = true;
  Future<void> Function(String, String)? _presenceForTesting;
  late final _presence = PresenceAnnouncements(
    selfId: memberId,
    speak: _presenceForTesting,
  );
  final Map<String, int> _memberSortOrders = {};
  final Map<String, String> _profileNames = {};
  final List<InternetChatMessage> _messages = [];
  int _unreadChatCount = 0;
  final Map<String, _IncomingInternetImage> _incomingImages = {};
  final Set<String> _speakingIds = {};
  final StreamController<double> _waveController =
      StreamController<double>.broadcast();

  InternetRoomSummary get summary => _summary!;
  List<InternetMember> get members => List.unmodifiable(_members);
  List<InternetChatMessage> get messages => List.unmodifiable(_messages);
  int get unreadChatCount => _unreadChatCount;
  InternetConnectionState get connectionState => _connectionState;
  VoiceMode get voiceMode => _voiceMode;
  bool get isMuted => _muted;
  bool get roomEnded => _roomEnded;
  bool get isMutedByHost => !isHost && !_policyCanSpeak;
  bool get awaitingMediaPermission => !isMutedByHost && !_mediaCanPublish;
  bool get canSpeak => !isMutedByHost && _mediaCanPublish;
  bool get isPttPressed => _pttPressed;
  bool get isSpeakerOn => _speakerOn;
  String? get hostInviteCode => isHost ? _inviteCode : null;
  InternetAudioProfile get audioProfile => _audioProfile;
  bool get isMeteredNetwork => _meteredNetwork;
  int get audioBitrate => _audioProfile.bitrateFor(metered: _meteredNetwork);
  bool get adminListening => _summary?.adminListening ?? false;
  Stream<double> get waveStream => _waveController.stream;

  static Future<InternetRoomSession> create({
    required InternetRoomApi api,
    required ServerProfile profile,
    required String nickname,
    required String deviceId,
    required String roomName,
    required int maxParticipants,
    required int hostDisconnectTimeoutMinutes,
    required RoomInvite invite,
    bool allowAdminListening = false,
  }) async {
    final networkFuture = _readNetworkAudioRecommendation();
    final random = Random.secure();
    final key = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    final credentials = await InternetInviteCredentials.derive(
      invite,
      InternetInviteCredentials.randomSalt(),
    );
    final grant = await api.createRoom(
      name: roomName,
      nickname: nickname,
      deviceId: deviceId,
      deviceProof: await ServerProfileStore().deviceProof(),
      maxParticipants: maxParticipants,
      hostDisconnectTimeoutMinutes: hostDisconnectTimeoutMinutes,
      joinSalt: credentials.salt,
      joinCredential: credentials.credential,
      wrappedRoomKey: await credentials.wrap(key),
      monitoringKey: allowAdminListening ? base64UrlEncode(key) : null,
    );
    final network = await networkFuture;
    final session = InternetRoomSession._(
      api: api,
      profile: profile,
      nickname: nickname,
      roomId: grant.room.id,
      memberId: grant.memberId,
      resumeToken: grant.resumeToken,
      isHost: true,
      inviteCode: invite.code,
      roomKey: key,
      audioProfile: network.$2,
      meteredNetwork: network.$1,
    ).._summary = grant.room;
    await session._start(grant);
    return session;
  }

  static Future<InternetRoomSession> join({
    required InternetRoomApi api,
    required ServerProfile profile,
    required String nickname,
    required String deviceId,
    required InternetRoomSummary room,
    required RoomInvite invite,
  }) async {
    final networkFuture = _readNetworkAudioRecommendation();
    final credentials = await InternetInviteCredentials.derive(
      invite,
      room.joinSalt,
    );
    final (grant, wrappedKey) = await api.joinRoom(
      roomId: room.id,
      nickname: nickname,
      deviceId: deviceId,
      deviceProof: await ServerProfileStore().deviceProof(),
      joinCredential: credentials.credential,
    );
    final roomKey = await credentials.unwrap(wrappedKey);
    final network = await networkFuture;
    final session = InternetRoomSession._(
      api: api,
      profile: profile,
      nickname: nickname,
      roomId: room.id,
      memberId: grant.memberId,
      resumeToken: grant.resumeToken,
      isHost: grant.room.isHost,
      inviteCode: invite.code,
      roomKey: roomKey,
      audioProfile: network.$2,
      meteredNetwork: network.$1,
    ).._summary = grant.room;
    await session._start(grant);
    return session;
  }

  static Future<WebSocket> _openSocket(
    ServerProfile profile,
    String value,
    String sessionToken,
  ) {
    var uri = Uri.parse(value);
    if (!uri.hasScheme) uri = Uri.parse(profile.baseUrl).resolveUri(uri);
    if (uri.scheme == 'https') uri = uri.replace(scheme: 'wss');
    if (uri.scheme == 'http') uri = uri.replace(scheme: 'ws');
    return WebSocket.connect(
      uri.toString(),
      headers: {
        if (profile.accessToken.isNotEmpty)
          'Authorization': 'Bearer ${profile.accessToken}',
        'X-Dawn-Session': sessionToken,
      },
    ).timeout(const Duration(seconds: 12));
  }

  Future<void> _start(InternetConnectionGrant grant) async {
    _chatCipher = await SessionCipher.fromKey(
      Spake2Keys.hkdf(_roomKey, 'DawnMesh internet chat v1'),
    );
    await _connectEvents(grant.eventsUrl);
    await _connectLiveKit(grant);
    await _refreshFeatures();
    _featuresTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_refreshFeatures()),
    );
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (results) => unawaited(_handleConnectivityChanged(results)),
    );
    await _backgroundControls.bind(_handleBackgroundCommand);
    await _syncBackgroundControls();
  }

  SessionCipher? _chatCipher;

  Future<void> _connectLiveKit(InternetConnectionGrant grant) async {
    // DawnMesh is an intercom rather than an exclusive phone call. Keeping
    // LiveKit's communication route while declining exclusive audio focus lets
    // turn-by-turn navigation remain audible and mix/duck according to Android.
    await AudioManager.instance.setAudioSessionOptions(
      const AudioSessionOptions.communication(
        android: AndroidAudioSessionConfiguration(
          audioMode: AndroidAudioMode.inCommunication,
          manageAudioFocus: false,
          focusMode: AndroidAudioFocusMode.gainTransientMayDuck,
          streamType: AndroidAudioStreamType.voiceCall,
          usageType: AndroidAudioAttributesUsageType.voiceCommunication,
          contentType: AndroidAudioAttributesContentType.speech,
        ),
      ),
    );
    final provider = await BaseKeyProvider.create();
    // Native LiveKit uses this passphrase's UTF-8 bytes as key material. The
    // browser must pass the same bytes explicitly instead of a JS string,
    // because its string overload selects a different PBKDF2 path.
    await provider.setKey(base64UrlEncode(_roomKey));
    final room = Room(
      roomOptions: RoomOptions(
        defaultAudioCaptureOptions: const AudioCaptureOptions(
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
          voiceIsolation: true,
          stopAudioCaptureOnMute: false,
        ),
        defaultAudioPublishOptions: AudioPublishOptions(
          encoding: AudioEncoding(maxBitrate: audioBitrate),
          dtx: true,
          // LiveKit disables RED when E2EE is enabled. Keep it explicit so the
          // profile's bandwidth estimate never assumes redundant packets.
          red: false,
        ),
        // Chat already has its own AES-GCM envelope. Limiting LiveKit E2EE to
        // media avoids a second, SDK-version-dependent data-channel wrapper.
        // ignore: deprecated_member_use
        e2eeOptions: E2EEOptions(keyProvider: provider),
      ),
    );
    final listener = room.createListener()
      ..on<RoomConnectedEvent>(
        (_) => _setConnectionState(InternetConnectionState.connected),
      )
      ..on<RoomReconnectingEvent>(
        (_) => _setConnectionState(InternetConnectionState.reconnecting),
      )
      ..on<RoomResumingEvent>(
        (_) => _setConnectionState(InternetConnectionState.reconnecting),
      )
      ..on<RoomReconnectedEvent>((_) {
        _reconnectStartedAt = null;
        _setConnectionState(InternetConnectionState.connected);
        unawaited(
          _setMediaCanPublish(
            room.localParticipant?.permissions.canPublish ?? false,
            forceSync: true,
          ),
        );
      })
      ..on<RoomDisconnectedEvent>((event) {
        if (!_closed) _beginFullReconnect('${event.reason ?? 'unknown'}');
      })
      ..on<ParticipantConnectedEvent>((_) {
        _refreshMembers();
        // A newcomer may have joined after this user last changed names.
        unawaited(_broadcastProfile());
      })
      ..on<ParticipantDisconnectedEvent>((_) => _refreshMembers())
      ..on<TrackSubscribedEvent>(
        (event) => _hybrid?.cloudTrackChanged(event.participant.identity),
      )
      ..on<ParticipantNameUpdatedEvent>((_) => _refreshMembers())
      ..on<ParticipantPermissionsUpdatedEvent>((event) {
        if (event.participant.identity == memberId) {
          unawaited(_setMediaCanPublish(event.permissions.canPublish));
        }
        _refreshMembers();
      })
      ..on<ActiveSpeakersChangedEvent>((event) {
        _speakingIds
          ..clear()
          ..addAll(event.speakers.map((item) => item.identity));
        final local = room.localParticipant;
        _waveController.add(
          local != null && _speakingIds.contains(local.identity)
              ? local.audioLevel
              : 0,
        );
        _refreshMembers();
      })
      ..on<DataReceivedEvent>(_onDataReceived);
    _livekitRoom = room;
    _listener = listener;
    await room.connect(
      grant.livekitUrl,
      grant.livekitToken,
      connectOptions: const ConnectOptions(autoSubscribe: true),
    );
    _audioChannel.setMethodCallHandler((call) async {
      if (call.method == 'internetAudioRouteChanged' && !_closed) {
        await recoverAudioRoute();
      }
    });
    await NoiseReductionSettings.startInternet();
    _noiseReductionAttached = true;
    _mediaCanPublish = room.localParticipant?.permissions.canPublish ?? true;
    _requestMediaPermission(force: true);
    await _syncMicrophone();
    await _applyAudioBitrate();
    _refreshMembers();
    unawaited(_broadcastProfile());
    AppLog.info(
      'DawnInternet',
      '已连接公网房「${summary.name}」，E2EE 已启用；音频=${_audioProfile.label}，'
          '网络=${_meteredNetwork ? '移动/计费' : 'Wi-Fi/有线'}，'
          '上限=${audioBitrate}bps，DTX=true',
    );
  }

  Future<void> _connectEvents(String eventsUrl) async {
    await _eventSubscription?.cancel();
    await _eventsSocket?.close();
    final socket = await _openSocket(profile, eventsUrl, resumeToken);
    if (_closed || _roomEnded) {
      await socket.close();
      return;
    }
    _eventReconnectStartedAt = null;
    _eventsSocket = socket;
    _eventSubscription = socket.listen(
      _handleManagementEvent,
      onDone: _scheduleEventReconnect,
      onError: (_, _) => _scheduleEventReconnect(),
    );
    final room = _livekitRoom;
    if (room?.connectionState == ConnectionState.connected) {
      unawaited(
        _setMediaCanPublish(
          room!.localParticipant?.permissions.canPublish ?? false,
          forceSync: true,
        ),
      );
    }
  }

  Future<void> _handleManagementEvent(dynamic raw) async {
    if (_closed || _roomEnded) return;
    try {
      final event = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (event['type']) {
        case 'snapshot':
          await _applySnapshot(event);
        case 'room_updated':
          _summary = InternetRoomSummary.fromJson(
            event['room'] as Map<String, dynamic>,
          );
          _presence.enabled = summary.presenceAnnouncementsEnabled;
          await _reconcileHybrid();
          notifyListeners();
        case 'member_left':
          if (!_managementRecovering &&
              _connectionState == InternetConnectionState.connected) {
            _presence.memberLeft(
              event['memberId'] as String? ?? '',
              event['nickname'] as String? ?? '成员',
              event['eventId'] as String? ?? '',
            );
          }
        case 'voice_policy':
          if (event['memberId'] == memberId) {
            _policyCanSpeak = event['canSpeak'] as bool? ?? false;
            if (!canSpeak) _pttPressed = false;
            await _syncMicrophone();
            await _syncBackgroundControls();
          }
          _applyMembers(event['members']);
          _requestMediaPermission();
        case 'role_changed':
          _hybridHostId = event['hostMemberId'] as String?;
          isHost = _hybridHostId == memberId;
          await _reconcileHybrid();
          _applyMembers(event['members']);
          await _syncMicrophone();
          await _syncBackgroundControls();
          _requestMediaPermission();
        case 'session_replaced':
          sessionReplaced = true;
          await _finishEndedRoom();
        case 'room_ended':
          await _finishEndedRoom();
      }
    } catch (error, stack) {
      AppLog.error('DawnInternet', '管理事件处理失败：$error', stack);
    }
  }

  @visibleForTesting
  Future<void> receiveManagementForTesting(Map<String, dynamic> event) =>
      _handleManagementEvent(jsonEncode(event));

  Future<void> setPresenceAnnouncements(bool enabled) async {
    if (!isHost || _closed || _roomEnded) return;
    if (!summary.presenceAnnouncementsSupported) {
      throw StateError('请先将服务端升级到 0.2.4 或更新版本');
    }
    final updated = await api.setPresenceAnnouncements(
      roomId,
      enabled,
      resumeToken,
    );
    if (_closed || _roomEnded) return;
    _summary = updated;
    _presence.enabled = updated.presenceAnnouncementsEnabled;
    notifyListeners();
  }

  @visibleForTesting
  Future<void> receiveRoomEndedForTesting() =>
      _handleManagementEvent(jsonEncode({'type': 'room_ended'}));

  @visibleForTesting
  Future<void> receiveVoicePolicyForTesting(bool value) =>
      _handleManagementEvent(
        jsonEncode({
          'type': 'voice_policy',
          'memberId': memberId,
          'canSpeak': value,
        }),
      );

  @visibleForTesting
  Future<void> receiveMediaPermissionForTesting(bool value) =>
      _setMediaCanPublish(value);

  Future<void> _setMediaCanPublish(bool value, {bool forceSync = false}) async {
    if (_closed || _roomEnded) return;
    _mediaCanPublish = value;
    _requestMediaPermission(force: forceSync);
    if (!canSpeak) _pttPressed = false;
    try {
      await _syncMicrophone();
      await _syncBackgroundControls();
    } catch (error, stack) {
      AppLog.error('DawnInternet', '媒体权限变化后更新麦克风失败：$error', stack);
    }
    notifyListeners();
  }

  Future<void> _applySnapshot(Map<String, dynamic> event) async {
    final room = event['room'];
    if (room is Map<String, dynamic>) {
      _summary = InternetRoomSummary.fromJson(room);
    }
    _managementRecovering = false;
    _presence.enabled = summary.presenceAnnouncementsEnabled;
    _hybridHostId = event['hostMemberId'] as String?;
    isHost = _hybridHostId == memberId;
    _policyCanSpeak = event['canSpeak'] as bool? ?? _policyCanSpeak;
    if (!canSpeak) _pttPressed = false;
    _applyMembers(event['members']);
    await _reconcileHybrid();
    _requestMediaPermission();
    await _syncMicrophone();
    await _syncBackgroundControls();
  }

  void _applyMembers(dynamic raw) {
    if (raw is! List<dynamic>) return;
    _hasManagementRoster = true;
    _managementMembers.clear();
    for (final entry in raw.indexed) {
      final (index, item) = entry;
      final value = item as Map<String, dynamic>;
      final id = value['id'] as String;
      final sortOrder = value['joinOrder'] as int? ?? index;
      _memberSortOrders[id] = sortOrder;
      _managementMembers[id] = InternetMember(
        id: id,
        nickname: _profileNames[id] ?? value['nickname'] as String? ?? id,
        isHost: value['isHost'] as bool? ?? false,
        canSpeak: value['canSpeak'] as bool? ?? true,
        isOnline: value['connected'] as bool? ?? true,
        sortOrder: sortOrder,
      );
    }
    final self = _managementMembers[memberId];
    if (self != null) _policyCanSpeak = self.canSpeak;
    if (!canSpeak) _pttPressed = false;
    _refreshMembers();
  }

  // Initial grants deliberately deny publishing. Keep retrying the server's
  // persisted policy after media/control recovery until the SDK confirms it.
  void _requestMediaPermission({bool force = false}) {
    _mediaPermissionTimer?.cancel();
    _mediaPermissionTimer = null;
    if (_closed ||
        _roomEnded ||
        _connectionState != InternetConnectionState.connected) {
      return;
    }
    if (_eventsSocket == null && _mediaReadyForTesting == null) return;
    final mismatch = _mediaCanPublish != !isMutedByHost;
    if (!force && !mismatch) return;
    try {
      if (_mediaReadyForTesting != null) {
        _mediaReadyForTesting!();
      } else {
        _eventsSocket!.add(
          jsonEncode({'type': 'media_ready', 'memberId': memberId}),
        );
      }
    } catch (error) {
      AppLog.warn('DawnInternet', '发言权限同步暂未发送：$error');
    }
    if (mismatch) {
      _mediaPermissionTimer = Timer(
        const Duration(seconds: 10),
        _requestMediaPermission,
      );
    }
  }

  void _scheduleEventReconnect() {
    if (_closed || _roomEnded || _eventReconnectTimer != null) return;
    _managementRecovering = true;
    _presence.suspend();
    _eventReconnectStartedAt ??= DateTime.now();
    if (DateTime.now().difference(_eventReconnectStartedAt!) >=
        const Duration(minutes: 30)) {
      _setConnectionState(InternetConnectionState.disconnected);
      return;
    }
    _eventReconnectTimer = Timer(const Duration(seconds: 2), () async {
      _eventReconnectTimer = null;
      if (_closed || _roomEnded) return;
      try {
        final grant = await _resume();
        await _connectEvents(grant.eventsUrl);
      } catch (error) {
        AppLog.warn('DawnInternet', '管理连接恢复失败：$error');
        _scheduleEventReconnect();
      }
    });
  }

  void _beginFullReconnect(String reason) {
    if (_closed || _roomEnded || _mediaReconnectPending) return;
    _reconnectStartedAt ??= DateTime.now();
    if (DateTime.now().difference(_reconnectStartedAt!) >=
        const Duration(minutes: 30)) {
      _setConnectionState(InternetConnectionState.disconnected);
      return;
    }
    _setConnectionState(InternetConnectionState.reconnecting);
    AppLog.warn('DawnInternet', '媒体连接中断：$reason；尝试恢复');
    _mediaReconnectPending = true;
    Future<void>.delayed(const Duration(seconds: 2), () async {
      if (_closed ||
          _roomEnded ||
          _connectionState != InternetConnectionState.reconnecting) {
        _mediaReconnectPending = false;
        return;
      }
      try {
        final grant = await _resume();
        if (_closed || _roomEnded) return;
        await _setHybridActive(false);
        await _listener?.dispose();
        await _livekitRoom?.dispose();
        await _connectLiveKit(grant);
        _reconnectStartedAt = null;
      } catch (error) {
        _mediaReconnectPending = false;
        if (!_closed && !_roomEnded) {
          _beginFullReconnect('$error');
        }
        return;
      }
      _mediaReconnectPending = false;
    });
  }

  Future<InternetConnectionGrant> _resume() {
    final active = _resumeFuture;
    if (active != null) return active;
    final completer = Completer<InternetConnectionGrant>();
    _resumeFuture = completer.future;
    unawaited(() async {
      try {
        final grant = await api.resume(
          roomId: roomId,
          memberId: memberId,
          resumeToken: resumeToken,
        );
        resumeToken = grant.resumeToken;
        completer.complete(grant);
      } catch (error, stack) {
        completer.completeError(error, stack);
      } finally {
        _resumeFuture = null;
      }
    }());
    return completer.future;
  }

  void _setConnectionState(InternetConnectionState value) {
    if (value != InternetConnectionState.connected && _hybrid != null) {
      _hybridRetryAfter = DateTime.now().add(const Duration(seconds: 60));
      unawaited(_setHybridActive(false));
    }
    if (_connectionState == value) return;
    _connectionState = value;
    if (value == InternetConnectionState.connected) {
      unawaited(_reconcileHybrid());
    }
    if (value != InternetConnectionState.connected) _presence.suspend();
    _refreshMembers();
  }

  void _refreshMembers() {
    final previousMembers = {for (final member in _members) member.id: member};
    final room = _livekitRoom;
    final participants = <String, Participant>{
      for (final participant
          in room?.remoteParticipants.values ?? <RemoteParticipant>[])
        participant.identity: participant,
      if (room?.localParticipant != null) memberId: room!.localParticipant!,
    };
    // The server roster is authoritative: offline members remain visible for
    // the recovery window, and a departed SDK participant cannot reappear.
    final ids = _hasManagementRoster
        ? _managementMembers.keys
        : participants.keys;
    var nextOrder = _memberSortOrders.values.fold<int>(
      0,
      (value, order) => order >= value ? order + 1 : value,
    );
    _members
      ..clear()
      ..addAll(
        ids.map((id) {
          final managed = _managementMembers[id];
          final participant = participants[id];
          final mediaKnown = room != null || _mediaMembersForTesting != null;
          final mediaConnected = _mediaMembersForTesting != null
              ? _mediaConnectedForTesting
              : room?.connectionState == ConnectionState.connected;
          final previous = previousMembers[id];
          final online = !mediaKnown
              ? (managed?.isOnline ?? true)
              : mediaConnected
              ? (_mediaMembersForTesting ?? participants.keys.toSet()).contains(
                  id,
                )
              : (previous?.isOnline ?? true);
          return InternetMember(
            id: id,
            nickname:
                _profileNames[id] ??
                managed?.nickname ??
                (participant?.name.isNotEmpty == true ? participant!.name : id),
            isHost: managed?.isHost ?? (id == memberId && isHost),
            canSpeak:
                managed?.canSpeak ??
                participant?.permissions.canPublish ??
                true,
            sortOrder:
                managed?.sortOrder ??
                _memberSortOrders.putIfAbsent(id, () => nextOrder++),
            isOnline: online,
            isSpeaking: online && _speakingIds.contains(id),
          );
        }),
      )
      ..sort(InternetMember.compareStable);
    if (!_closed &&
        !_roomEnded &&
        !_managementRecovering &&
        _connectionState == InternetConnectionState.connected) {
      _presence.enabled = summary.presenceAnnouncementsEnabled;
      _presence.observe(_members);
    }
    notifyListeners();
  }

  void _onDataReceived(DataReceivedEvent event) {
    if (event.topic == 'dawnmesh.hybrid.v1') {
      unawaited(_receiveHybridSignal(event));
    } else if (event.topic == 'dawnmesh.chat.v1') {
      unawaited(_decryptChat(event));
    } else if (event.topic == 'dawnmesh.image.v1') {
      unawaited(_decryptImageChunk(event));
    } else if (event.topic == 'dawnmesh.profile.v1') {
      unawaited(_decryptProfile(event));
    }
  }

  Future<void> _decryptProfile(DataReceivedEvent event) async {
    try {
      final senderId = event.participant?.identity;
      final cipher = _chatCipher;
      if (senderId == null || cipher == null || event.data.length < 29) return;
      final clear = await cipher.decrypt(
        EncryptedPacket(
          nonce: Uint8List.fromList(event.data.sublist(0, 12)),
          ciphertext: Uint8List.fromList(event.data.sublist(12)),
        ),
        associatedData: Uint8List.fromList(
          utf8.encode('dawnmesh.profile.v1\u0000$senderId'),
        ),
      );
      final name = utf8.decode(clear).trim();
      if (name.isEmpty || utf8.encode(name).length > 64) return;
      _profileNames[senderId] = name;
      _refreshMembers();
    } catch (error) {
      AppLog.warn('DawnInternet', '忽略无效昵称更新：$error');
    }
  }

  Future<void> _broadcastProfile() async {
    final cipher = _chatCipher;
    final participant = _livekitRoom?.localParticipant;
    if (cipher == null || participant == null || _closed) return;
    final encrypted = await cipher.encrypt(
      Uint8List.fromList(utf8.encode(_nickname)),
      associatedData: Uint8List.fromList(
        utf8.encode('dawnmesh.profile.v1\u0000$memberId'),
      ),
    );
    await participant.publishData(
      [...encrypted.nonce, ...encrypted.ciphertext],
      reliable: true,
      topic: 'dawnmesh.profile.v1',
    );
  }

  Future<void> _decryptChat(DataReceivedEvent event) async {
    try {
      final senderId = event.participant?.identity;
      final cipher = _chatCipher;
      if (senderId == null || cipher == null || event.data.length < 29) return;
      final clear = await cipher.decrypt(
        EncryptedPacket(
          nonce: Uint8List.fromList(event.data.sublist(0, 12)),
          ciphertext: Uint8List.fromList(event.data.sublist(12)),
        ),
        associatedData: Uint8List.fromList(
          utf8.encode('dawnmesh.chat.v1\u0000$senderId'),
        ),
      );
      final value = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
      if (value['senderId'] != senderId ||
          value['id'] is! String ||
          (value['id'] as String).length > 160 ||
          value['text'] is! String ||
          utf8.encode(value['text'] as String).length > 1000 ||
          value['sentAt'] is! int) {
        throw const FormatException('invalid encrypted chat payload');
      }
      _appendChatMessage(
        InternetChatMessage(
          id: value['id'] as String,
          senderId: senderId,
          senderName:
              value['senderName'] as String? ??
              event.participant?.name ??
              senderId,
          text: value['text'] as String,
          sentAt: DateTime.fromMillisecondsSinceEpoch(value['sentAt'] as int),
          isMine: senderId == memberId,
        ),
        isIncoming: senderId != memberId,
      );
    } catch (error) {
      AppLog.warn('DawnInternet', '忽略无效聊天数据：$error');
    }
  }

  Future<void> sendChat(String text) async {
    if (_closed || _roomEnded) return;
    final value = text.trim();
    if (value.isEmpty || utf8.encode(value).length > 1000) return;
    final now = DateTime.now();
    final id = '${now.microsecondsSinceEpoch}-$memberId';
    final message = {
      'id': id,
      'senderId': memberId,
      'senderName': nickname,
      'text': value,
      'sentAt': now.millisecondsSinceEpoch,
    };
    final cipher = _chatCipher;
    if (cipher == null) return;
    final encrypted = await cipher.encrypt(
      Uint8List.fromList(utf8.encode(jsonEncode(message))),
      associatedData: Uint8List.fromList(
        utf8.encode('dawnmesh.chat.v1\u0000$memberId'),
      ),
    );
    await _livekitRoom?.localParticipant?.publishData(
      [...encrypted.nonce, ...encrypted.ciphertext],
      reliable: true,
      topic: 'dawnmesh.chat.v1',
    );
    _appendChatMessage(
      InternetChatMessage(
        id: id,
        senderId: memberId,
        senderName: nickname,
        text: value,
        sentAt: now,
        isMine: true,
      ),
      isIncoming: false,
    );
  }

  Future<void> sendChatImage({
    required Uint8List bytes,
    required String mimeType,
    required String name,
  }) async {
    if (_closed || _roomEnded) return;
    if (bytes.isEmpty || bytes.length > ChatImageChunkPayload.maxImageBytes) {
      throw ArgumentError('图片不能超过 192 KB。');
    }
    final format = ChatImageFormat.fromMimeType(mimeType);
    final cipher = _chatCipher;
    final participant = _livekitRoom?.localParticipant;
    if (format == null || cipher == null || participant == null) {
      throw StateError('图片发送通道尚未就绪。');
    }
    final now = DateTime.now();
    final transferId = now.microsecondsSinceEpoch & 0xffffffff;
    final safeName = _safeInternetImageName(name, format);
    final chunkCount =
        (bytes.length + _InternetImageChunk.maxChunkBytes - 1) ~/
        _InternetImageChunk.maxChunkBytes;
    for (var index = 0; index < chunkCount; index++) {
      final start = index * _InternetImageChunk.maxChunkBytes;
      final end = min(start + _InternetImageChunk.maxChunkBytes, bytes.length);
      final clear = _InternetImageChunk(
        transferId: transferId,
        timestampMs: now.millisecondsSinceEpoch,
        chunkIndex: index,
        chunkCount: chunkCount,
        format: format,
        name: safeName,
        data: Uint8List.sublistView(bytes, start, end),
      ).encode();
      final encrypted = await cipher.encrypt(
        clear,
        associatedData: Uint8List.fromList(
          utf8.encode('dawnmesh.image.v1\u0000$memberId'),
        ),
      );
      await participant.publishData(
        [...encrypted.nonce, ...encrypted.ciphertext],
        reliable: true,
        topic: 'dawnmesh.image.v1',
      );
    }
    _appendChatMessage(
      InternetChatMessage(
        id: '$transferId-$memberId-image',
        senderId: memberId,
        senderName: nickname,
        text: '',
        sentAt: now,
        isMine: true,
        imageBytes: Uint8List.fromList(bytes),
        imageMimeType: mimeType,
        imageName: safeName,
      ),
      isIncoming: false,
    );
  }

  Future<void> _decryptImageChunk(DataReceivedEvent event) async {
    try {
      final senderId = event.participant?.identity;
      final cipher = _chatCipher;
      if (senderId == null || cipher == null || event.data.length < 29) return;
      final clear = await cipher.decrypt(
        EncryptedPacket(
          nonce: Uint8List.fromList(event.data.sublist(0, 12)),
          ciphertext: Uint8List.fromList(event.data.sublist(12)),
        ),
        associatedData: Uint8List.fromList(
          utf8.encode('dawnmesh.image.v1\u0000$senderId'),
        ),
      );
      final chunk = _InternetImageChunk.decode(clear);
      if (chunk == null) return;
      final now = DateTime.now();
      _incomingImages.removeWhere(
        (_, transfer) =>
            now.difference(transfer.lastUpdated) > const Duration(minutes: 1),
      );
      if (_incomingImages.length >= 8) {
        final oldest = _incomingImages.entries.reduce(
          (a, b) => a.value.lastUpdated.isBefore(b.value.lastUpdated) ? a : b,
        );
        _incomingImages.remove(oldest.key);
      }
      final key = '$senderId:${chunk.transferId}';
      final transfer = _incomingImages.putIfAbsent(
        key,
        () => _IncomingInternetImage(chunk),
      );
      if (!transfer.accepts(chunk)) {
        _incomingImages.remove(key);
        return;
      }
      transfer.add(chunk);
      if (!transfer.isComplete) return;
      _incomingImages.remove(key);
      final bytes = transfer.assemble();
      if (bytes == null) return;
      _appendChatMessage(
        InternetChatMessage(
          id: '${chunk.transferId}-$senderId-image',
          senderId: senderId,
          senderName: event.participant?.name ?? senderId,
          text: '',
          sentAt: DateTime.fromMillisecondsSinceEpoch(chunk.timestampMs),
          isMine: senderId == memberId,
          imageBytes: bytes,
          imageMimeType: chunk.format.mimeType,
          imageName: chunk.name,
        ),
        isIncoming: senderId != memberId,
      );
    } catch (error) {
      AppLog.warn('DawnInternet', '忽略无效图片数据：$error');
    }
  }

  void _appendChatMessage(
    InternetChatMessage message, {
    required bool isIncoming,
  }) {
    _messages.add(message);
    if (_messages.length > 100) _messages.removeAt(0);
    if (isIncoming) _unreadChatCount++;
    notifyListeners();
  }

  @visibleForTesting
  void receiveChatForTesting({
    String senderId = 'remote-member',
    String senderName = '远端成员',
    String text = '测试消息',
  }) => _appendChatMessage(
    InternetChatMessage(
      id: 'test-${_messages.length}',
      senderId: senderId,
      senderName: senderName,
      text: text,
      sentAt: DateTime.now(),
      isMine: false,
    ),
    isIncoming: true,
  );

  void markChatRead() {
    if (_unreadChatCount == 0) return;
    _unreadChatCount = 0;
    notifyListeners();
  }

  Future<void> setVoiceMode(VoiceMode value) async {
    if (_voiceMode == value || _closed || _roomEnded) return;
    _voiceMode = value;
    _pttPressed = false;
    await _syncMicrophone();
    await _syncBackgroundControls();
    notifyListeners();
  }

  /// Changes the visible identity while keeping the media session alive.
  Future<void> updateNickname(String value) async {
    final name = value.trim();
    if (_closed || name.isEmpty || utf8.encode(name).length > 64) return;
    if (_nickname == name) return;
    _nickname = name;
    _profileNames[memberId] = name;
    _refreshMembers();
    // The room-level encrypted packet is the compatibility path and reaches
    // current peers immediately, so never wait for an optional SDK feature.
    await _broadcastProfile();
    unawaited(_updateLiveKitName(name));
  }

  Future<void> _updateLiveKitName(String name) async {
    try {
      // Newer servers grant this LiveKit permission, giving late joiners the
      // updated name directly. Existing servers continue through the profile
      // packet above without making nickname editing feel delayed.
      await _livekitRoom?.localParticipant?.setName(name);
    } catch (error) {
      AppLog.warn('DawnInternet', '媒体服务暂不支持直接改名，使用房间内同步：$error');
    }
  }

  Future<void> setAudioProfile(InternetAudioProfile value) async {
    if (_closed || _roomEnded) return;
    _audioProfileManuallySelected = true;
    if (_audioProfile == value) return;
    _audioProfile = value;
    await _applyAudioBitrate();
    AppLog.info(
      'DawnInternet',
      '公网音频档位=${value.name}，网络=${_meteredNetwork ? '移动/计费' : 'Wi-Fi/有线'}，上限=${audioBitrate}bps，DTX=true',
    );
    notifyListeners();
  }

  Future<void> setPtt(bool pressed) async {
    if (_voiceMode != VoiceMode.pushToTalk ||
        _closed ||
        _roomEnded ||
        !canSpeak ||
        _muted) {
      pressed = false;
    }
    if (_pttPressed == pressed) return;
    _pttPressed = pressed;
    await _syncMicrophone();
    await _syncBackgroundControls();
    notifyListeners();
  }

  Future<void> toggleMute() async {
    _muted = !_muted;
    if (_muted) _pttPressed = false;
    await _syncMicrophone();
    await _syncBackgroundControls();
    notifyListeners();
  }

  Future<void> _syncMicrophone() {
    final task = (_microphoneQueue ?? Future<void>.value()).then(
      (_) => _applyMicrophone(),
    );
    late final Future<void> settled;
    settled = task.then(
      (_) {
        if (identical(_microphoneQueue, settled)) _microphoneQueue = null;
      },
      onError: (Object error, StackTrace _) {
        if (identical(_microphoneQueue, settled)) _microphoneQueue = null;
        AppLog.warn('DawnInternet', '更新麦克风失败：$error');
      },
    );
    _microphoneQueue = settled;
    return task;
  }

  bool get _shouldSendVoice =>
      !_closed &&
      !_roomEnded &&
      canSpeak &&
      !_muted &&
      (_voiceMode == VoiceMode.automatic || _pttPressed);

  Future<void> _applyMicrophone() async {
    if (_closed || _roomEnded) return;
    if (_audioRecoveryPending && _shouldSendVoice) {
      _audioRecoveryPending = false;
      try {
        final recover = _audioRecoveryForTesting;
        if (recover != null) {
          await recover();
        } else {
          final track = _livekitRoom?.localParticipant
              ?.getTrackPublicationBySource(TrackSource.microphone)
              ?.track;
          if (track is LocalAudioTrack) {
            await _hybrid?.setSending(false);
            await track.restartTrack();
            await NoiseReductionSettings.startInternet();
            await AudioManager.instance.setSpeakerOutputPreferred(
              _speakerOn,
              force: false,
            );
            AppLog.info('DawnInternet', '耳机连接变化后已重建麦克风采集');
          }
        }
      } catch (_) {
        _audioRecoveryPending = true;
        rethrow;
      }
    }
    // A mute, PTT release or policy update may arrive while capture restarts.
    final enabled = _shouldSendVoice;
    final testMicrophone = _microphoneForTesting;
    if (testMicrophone != null) {
      await testMicrophone(enabled);
    } else {
      await _livekitRoom?.localParticipant?.setMicrophoneEnabled(enabled);
    }
    await _hybrid?.setSending(_shouldSendVoice);
    if (_shouldSendVoice) await _applyAudioBitrate();
  }

  Future<void> _applyAudioBitrate() async {
    final publication = _livekitRoom?.localParticipant
        ?.getTrackPublicationBySource(TrackSource.microphone);
    final sender = publication?.track?.sender;
    if (sender == null) return;
    final parameters = sender.parameters;
    final encodings = parameters.encodings;
    if (encodings == null || encodings.isEmpty) return;
    for (final encoding in encodings) {
      encoding.maxBitrate = audioBitrate;
    }
    final applied = await sender.setParameters(parameters);
    if (!applied) {
      AppLog.warn('DawnInternet', 'WebRTC 未接受 ${audioBitrate}bps 音频码率更新');
    }
  }

  static bool _isMeteredConnection(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet)) {
      return false;
    }
    // VPN/other cannot reliably reveal the underlying bearer. Treat unknown
    // transports as metered so they do not accidentally consume mobile data.
    return true;
  }

  static Future<(bool, InternetAudioProfile)>
  _readNetworkAudioRecommendation() async {
    try {
      final metered = _isMeteredConnection(
        await Connectivity().checkConnectivity(),
      );
      return (
        metered,
        InternetAudioProfileDetails.recommended(metered: metered),
      );
    } catch (error) {
      AppLog.warn('DawnInternet', '无法识别当前网络，默认使用省流档：$error');
      return (true, InternetAudioProfile.dataSaver);
    }
  }

  Future<void> _handleConnectivityChanged(
    List<ConnectivityResult> results,
  ) async {
    if (_closed || _roomEnded) return;
    final metered = _isMeteredConnection(results);
    final recommended = InternetAudioProfileDetails.recommended(
      metered: metered,
    );
    final nextProfile = _audioProfileManuallySelected
        ? _audioProfile
        : recommended;
    if (_meteredNetwork == metered && _audioProfile == nextProfile) return;
    _meteredNetwork = metered;
    _audioProfile = nextProfile;
    await _applyAudioBitrate();
    AppLog.info(
      'DawnInternet',
      '网络切换为 ${metered ? '移动/计费网络' : 'Wi-Fi/有线网络'}，公网音频调整为 ${_audioProfile.label} ${audioBitrate}bps',
    );
    notifyListeners();
  }

  Future<void> setSpeakerphone(bool enabled) async {
    _speakerOn = enabled;
    await AudioManager.instance.setSpeakerOutputPreferred(
      enabled,
      force: false,
    );
    notifyListeners();
  }

  Future<void> _handleBackgroundCommand(String method, dynamic value) async {
    switch (method) {
      case 'automatic':
        await setVoiceMode(
          value == true ? VoiceMode.automatic : VoiceMode.pushToTalk,
        );
      case 'ptt':
        await setPtt(value == true);
      case 'mute':
        if ((value == true) != _muted) await toggleMute();
    }
  }

  @visibleForTesting
  Future<void> handleBackgroundCommandForTesting(
    String method,
    dynamic value,
  ) => _handleBackgroundCommand(method, value);

  Future<void> _syncBackgroundControls() => _backgroundControls.update(
    bluetooth: false,
    internet: true,
    automatic: _voiceMode == VoiceMode.automatic,
    pressed: _pttPressed,
    muted: _muted || !canSpeak,
  );

  Future<void> renameRoom(String value) =>
      api.renameRoom(roomId, value.trim(), resumeToken);
  Future<void> setMemberCanSpeak(String targetId, bool value) =>
      api.setVoicePolicy(roomId, targetId, value, resumeToken);
  Future<void> transferHost(String targetId) =>
      api.handover(roomId, targetId, resumeToken);

  Future<void> leave({bool endRoom = false}) async {
    if (_closed) return;
    _presence.dispose();
    _mediaPermissionTimer?.cancel();
    try {
      await api.leave(
        roomId,
        memberId,
        resumeToken,
        endRoom: endRoom && isHost,
      );
    } catch (error) {
      AppLog.warn('DawnInternet', '离房通知失败：$error');
    }
    await disposeSession();
  }

  /// Ends the server room while keeping its in-memory chat readable until the
  /// user explicitly exits the ended room page.
  Future<void> endRoom() async {
    if (_closed || _roomEnded || !isHost) return;
    await api.leave(roomId, memberId, resumeToken, endRoom: true);
    await _finishEndedRoom();
  }

  Future<void> _stopNoiseReduction() async {
    if (!_noiseReductionAttached) return;
    _noiseReductionAttached = false;
    await NoiseReductionSettings.stopInternet();
  }

  Future<void> _finishEndedRoom() {
    if (_roomEndTask != null) return _roomEndTask!;
    if (_roomEnded || _closed) return Future<void>.value();
    final task = _cleanupEndedRoom();
    late final Future<void> settled;
    settled = task.whenComplete(() {
      if (identical(_roomEndTask, settled)) _roomEndTask = null;
    });
    _roomEndTask = settled;
    return settled;
  }

  Future<void> _cleanupEndedRoom() async {
    if (_closed || _roomEnded) return;
    _roomEnded = true;
    _featuresTimer?.cancel();
    await _setHybridActive(false);
    await _microphoneQueue;
    _presence.dispose();
    _mediaPermissionTimer?.cancel();
    _eventReconnectTimer?.cancel();
    _pttPressed = false;
    if (_connectionState == InternetConnectionState.disconnected) {
      notifyListeners();
    } else {
      _setConnectionState(InternetConnectionState.disconnected);
    }
    await _livekitRoom?.localParticipant?.setMicrophoneEnabled(false);
    await _backgroundControls.close();
    final listener = _listener;
    _listener = null;
    await listener?.dispose();
    final room = _livekitRoom;
    _livekitRoom = null;
    await room?.disconnect();
    await room?.dispose();
    await _stopNoiseReduction();
    final subscription = _eventSubscription;
    _eventSubscription = null;
    await subscription?.cancel();
    final socket = _eventsSocket;
    _eventsSocket = null;
    await socket?.close();
    AppLog.warn('DawnInternet', '房间已解散，消息保留到用户退出');
  }

  Future<void> disposeSession() async {
    await _roomEndTask;
    if (_closed) return;
    _closed = true;
    _featuresTimer?.cancel();
    await _setHybridActive(false);
    _audioChannel.setMethodCallHandler(null);
    await _microphoneQueue;
    _presence.dispose();
    _mediaPermissionTimer?.cancel();
    _eventReconnectTimer?.cancel();
    await _connectivitySubscription?.cancel();
    await _backgroundControls.close();
    await _eventSubscription?.cancel();
    await _eventsSocket?.close();
    await _listener?.dispose();
    await _livekitRoom?.disconnect();
    await _livekitRoom?.dispose();
    await _stopNoiseReduction();
    await AudioManager.instance.setAudioSessionManagementMode(
      AudioSessionManagementMode.automatic,
    );
    await _waveController.close();
    _incomingImages.clear();
    _messages.clear();
    _unreadChatCount = 0;
    _roomKey.fillRange(0, _roomKey.length, 0);
    api.close();
  }
}

String _safeInternetImageName(String raw, ChatImageFormat format) {
  final extension = switch (format) {
    ChatImageFormat.jpeg => 'jpg',
    ChatImageFormat.png => 'png',
    ChatImageFormat.webp => 'webp',
  };
  final cleaned = raw
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')
      .replaceAll(RegExp(r'_+'), '_');
  final stem = cleaned.isEmpty ? 'DawnMesh_image' : cleaned;
  return '${stem.substring(0, min(20, stem.length))}.$extension';
}

class _InternetImageChunk {
  const _InternetImageChunk({
    required this.transferId,
    required this.timestampMs,
    required this.chunkIndex,
    required this.chunkCount,
    required this.format,
    required this.name,
    required this.data,
  });

  static const int version = 1;
  static const int headerBytes = 19;
  static const int maxNameBytes = 32;
  static const int maxChunkBytes = 12 * 1024;
  static const int maxChunkCount = 32;

  final int transferId;
  final int timestampMs;
  final int chunkIndex;
  final int chunkCount;
  final ChatImageFormat format;
  final String name;
  final Uint8List data;

  Uint8List encode() {
    final nameBytes = utf8.encode(name);
    if (nameBytes.isEmpty ||
        nameBytes.length > maxNameBytes ||
        chunkCount <= 0 ||
        chunkCount > maxChunkCount ||
        chunkIndex < 0 ||
        chunkIndex >= chunkCount ||
        data.isEmpty ||
        data.length > maxChunkBytes) {
      throw ArgumentError('invalid internet image chunk');
    }
    final result = Uint8List(headerBytes + nameBytes.length + data.length);
    final view = ByteData.sublistView(result);
    result[0] = version;
    view.setUint32(1, transferId, Endian.big);
    view.setUint64(5, timestampMs, Endian.big);
    view.setUint16(13, chunkIndex, Endian.big);
    view.setUint16(15, chunkCount, Endian.big);
    result[17] = format.value;
    result[18] = nameBytes.length;
    result.setRange(headerBytes, headerBytes + nameBytes.length, nameBytes);
    result.setRange(headerBytes + nameBytes.length, result.length, data);
    return result;
  }

  static _InternetImageChunk? decode(Uint8List bytes) {
    if (bytes.length <= headerBytes || bytes[0] != version) return null;
    final view = ByteData.sublistView(bytes);
    final index = view.getUint16(13, Endian.big);
    final count = view.getUint16(15, Endian.big);
    final format = ChatImageFormat.fromValue(bytes[17]);
    final nameLength = bytes[18];
    if (format == null ||
        nameLength == 0 ||
        nameLength > maxNameBytes ||
        count == 0 ||
        count > maxChunkCount ||
        index >= count ||
        bytes.length <= headerBytes + nameLength ||
        bytes.length > headerBytes + nameLength + maxChunkBytes) {
      return null;
    }
    try {
      return _InternetImageChunk(
        transferId: view.getUint32(1, Endian.big),
        timestampMs: view.getUint64(5, Endian.big),
        chunkIndex: index,
        chunkCount: count,
        format: format,
        name: utf8.decode(
          bytes.sublist(headerBytes, headerBytes + nameLength),
          allowMalformed: false,
        ),
        data: Uint8List.fromList(bytes.sublist(headerBytes + nameLength)),
      );
    } catch (_) {
      return null;
    }
  }
}

class _IncomingInternetImage {
  _IncomingInternetImage(_InternetImageChunk first)
    : transferId = first.transferId,
      timestampMs = first.timestampMs,
      chunkCount = first.chunkCount,
      format = first.format,
      name = first.name,
      chunks = List<Uint8List?>.filled(first.chunkCount, null),
      lastUpdated = DateTime.now();

  final int transferId;
  final int timestampMs;
  final int chunkCount;
  final ChatImageFormat format;
  final String name;
  final List<Uint8List?> chunks;
  DateTime lastUpdated;
  int totalBytes = 0;

  bool accepts(_InternetImageChunk chunk) =>
      chunk.transferId == transferId &&
      chunk.timestampMs == timestampMs &&
      chunk.chunkCount == chunkCount &&
      chunk.format == format &&
      chunk.name == name;

  void add(_InternetImageChunk chunk) {
    if (chunks[chunk.chunkIndex] != null) return;
    chunks[chunk.chunkIndex] = Uint8List.fromList(chunk.data);
    totalBytes += chunk.data.length;
    lastUpdated = DateTime.now();
  }

  bool get isComplete => chunks.every((chunk) => chunk != null);

  Uint8List? assemble() {
    if (!isComplete || totalBytes > ChatImageChunkPayload.maxImageBytes) {
      return null;
    }
    final result = Uint8List(totalBytes);
    var offset = 0;
    for (final chunk in chunks) {
      result.setRange(offset, offset + chunk!.length, chunk);
      offset += chunk.length;
    }
    return result;
  }
}
