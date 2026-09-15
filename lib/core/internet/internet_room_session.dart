// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import '../diagnostics/app_log.dart';
import '../platform/background_call_controls.dart';
import '../security/room_invite.dart';
import '../security/session_crypto.dart';
import '../security/spake2.dart';
import '../session/room_session.dart' show VoiceMode;
import 'internet_audio_profile.dart';
import 'internet_models.dart';
import 'internet_room_api.dart';

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
  });
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime sentAt;
  final bool isMine;
}

class InternetRoomSession extends ChangeNotifier {
  InternetRoomSession._({
    required this.api,
    required this.profile,
    required this.nickname,
    required this.roomId,
    required this.memberId,
    required this.resumeToken,
    required this.isHost,
    required this._inviteCode,
    required this._roomKey,
    required this._audioProfile,
    required this._meteredNetwork,
  });

  final InternetRoomApi api;
  final ServerProfile profile;
  final String nickname;
  final String roomId;
  final String memberId;
  String resumeToken;
  bool isHost;
  final String _inviteCode;
  final Uint8List _roomKey;
  final BackgroundCallControls _backgroundControls = BackgroundCallControls(
    Object(),
  );

  Room? _livekitRoom;
  EventsListener<RoomEvent>? _listener;
  WebSocket? _eventsSocket;
  StreamSubscription<dynamic>? _eventSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _eventReconnectTimer;
  Future<InternetConnectionGrant>? _resumeFuture;
  DateTime? _reconnectStartedAt;
  bool _closed = false;
  bool _roomEnded = false;
  bool _muted = false;
  bool _canSpeak = true;
  bool _pttPressed = false;
  bool _speakerOn = true;
  InternetAudioProfile _audioProfile;
  bool _meteredNetwork;
  bool _audioProfileManuallySelected = false;
  VoiceMode _voiceMode = VoiceMode.pushToTalk;
  InternetConnectionState _connectionState = InternetConnectionState.connecting;
  InternetRoomSummary? _summary;
  final List<InternetMember> _members = [];
  final Map<String, int> _memberSortOrders = {};
  final List<InternetChatMessage> _messages = [];
  final Map<String, _HostAdmission> _hostAdmissions = {};
  final Set<String> _speakingIds = {};
  final StreamController<double> _waveController =
      StreamController<double>.broadcast();

  InternetRoomSummary get summary => _summary!;
  List<InternetMember> get members => List.unmodifiable(_members);
  List<InternetChatMessage> get messages => List.unmodifiable(_messages);
  InternetConnectionState get connectionState => _connectionState;
  VoiceMode get voiceMode => _voiceMode;
  bool get isMuted => _muted;
  bool get canSpeak => _canSpeak;
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
    final grant = await api.createRoom(
      name: roomName,
      nickname: nickname,
      deviceId: deviceId,
      maxParticipants: maxParticipants,
      hostDisconnectTimeoutMinutes: hostDisconnectTimeoutMinutes,
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
    await session._start(grant, invite: invite);
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
    final admission = await api.beginAdmission(
      roomId: room.id,
      nickname: nickname,
      deviceId: deviceId,
    );
    final result = await _completeAdmission(profile, admission, invite);
    final network = await networkFuture;
    final session =
        InternetRoomSession._(
            api: api,
            profile: profile,
            nickname: nickname,
            roomId: room.id,
            memberId: result.grant.memberId,
            resumeToken: result.grant.resumeToken,
            isHost: false,
            inviteCode: invite.code,
            roomKey: result.roomKey,
            audioProfile: network.$2,
            meteredNetwork: network.$1,
          )
          .._summary = result.grant.room
          .._hostPasswordScalar = result.passwordScalar;
    await session._start(result.grant);
    return session;
  }

  static Future<_AdmissionResult> _completeAdmission(
    ServerProfile profile,
    InternetAdmissionGrant admission,
    RoomInvite invite,
  ) async {
    final scalar = await invite.passwordScalar();
    final pake = Spake2(isA: true, passwordScalar: scalar);
    final socket = await _openSocket(
      profile,
      admission.eventsUrl,
      admission.resumeToken,
    );
    final completer = Completer<_AdmissionResult>();
    Spake2Keys? keys;
    late final StreamSubscription<dynamic> subscription;
    subscription = socket.listen(
      (raw) async {
        try {
          final event = jsonDecode(raw as String) as Map<String, dynamic>;
          if (event['admissionId'] != admission.admissionId) return;
          final type = event['type'];
          if (type == 'pake_reply') {
            final body = base64Decode(event['body'] as String);
            if (body.length != 97) {
              throw const FormatException('PAKE reply length');
            }
            final identities = _pakeIdentities(
              profile.instanceId ?? '',
              admission.room.id,
              admission.admissionId,
              admission.memberId,
            );
            keys = pake.finish(
              Uint8List.sublistView(body, 0, 65),
              a: identities.$1,
              b: identities.$2,
            );
            if (!Spake2Keys.equal(body.sublist(65), keys!.confirmB)) {
              throw const FormatException('邀请码校验失败');
            }
            socket.add(
              jsonEncode({
                'type': 'pake_confirm',
                'admissionId': admission.admissionId,
                'body': base64Encode(keys!.confirmA),
              }),
            );
          } else if (type == 'pake_key') {
            final activeKeys = keys;
            if (activeKeys == null) throw const FormatException('PAKE state');
            final packet = base64Decode(event['body'] as String);
            if (packet.length < 29) {
              throw const FormatException('encrypted key length');
            }
            final cipher = await SessionCipher.fromKey(
              Spake2Keys.hkdf(
                activeKeys.sharedKey,
                'DawnMesh internet room key wrapping v1',
              ),
            );
            final roomKey = await cipher.decrypt(
              EncryptedPacket(
                nonce: Uint8List.sublistView(packet, 0, 12),
                ciphertext: Uint8List.sublistView(packet, 12),
              ),
              associatedData: Uint8List.fromList(
                utf8.encode(admission.admissionId),
              ),
            );
            final grant = InternetConnectionGrant.fromJson(
              event['connection'] as Map<String, dynamic>,
            );
            if (!completer.isCompleted) {
              completer.complete(
                _AdmissionResult(grant, Uint8List.fromList(roomKey), scalar),
              );
            }
          } else if (type == 'admission_rejected') {
            throw InternetApiException(event['error'] as String? ?? '邀请码验证失败');
          }
        } catch (error, stack) {
          if (!completer.isCompleted) completer.completeError(error, stack);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(const InternetApiException('房主连接已中断'));
        }
      },
    );
    socket.add(
      jsonEncode({
        'type': 'pake_hello',
        'admissionId': admission.admissionId,
        'body': base64Encode(pake.message),
      }),
    );
    try {
      return await completer.future.timeout(const Duration(seconds: 20));
    } finally {
      await subscription.cancel();
      await socket.close();
    }
  }

  static (Uint8List, Uint8List) _pakeIdentities(
    String instanceId,
    String roomId,
    String admissionId,
    String memberId,
  ) => (
    Uint8List.fromList(
      utf8.encode(
        'DawnMesh internet PAKE v1 client\u0000$instanceId\u0000$roomId\u0000$admissionId\u0000$memberId',
      ),
    ),
    Uint8List.fromList(
      utf8.encode(
        'DawnMesh internet PAKE v1 host\u0000$instanceId\u0000$roomId',
      ),
    ),
  );

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

  Future<void> _start(
    InternetConnectionGrant grant, {
    RoomInvite? invite,
  }) async {
    _chatCipher = await SessionCipher.fromKey(
      Spake2Keys.hkdf(_roomKey, 'DawnMesh internet chat v1'),
    );
    if (isHost) {
      if (invite == null) throw StateError('Host invite is required');
      _hostPasswordScalar = await invite.passwordScalar();
    }
    await _connectEvents(grant.eventsUrl);
    await _connectLiveKit(grant);
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (results) => unawaited(_handleConnectivityChanged(results)),
    );
    await _backgroundControls.bind(_handleBackgroundCommand);
    await _syncBackgroundControls();
  }

  BigInt? _hostPasswordScalar;
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
        encryption: E2EEOptions(keyProvider: provider),
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
      })
      ..on<RoomDisconnectedEvent>((event) {
        if (!_closed) _beginFullReconnect('${event.reason ?? 'unknown'}');
      })
      ..on<ParticipantConnectedEvent>((_) => _refreshMembers())
      ..on<ParticipantDisconnectedEvent>((_) => _refreshMembers())
      ..on<ParticipantPermissionsUpdatedEvent>((event) {
        if (event.participant.identity == memberId) {
          _canSpeak = event.permissions.canPublish;
          if (!_canSpeak) unawaited(_applyMicrophone(false));
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
    _eventsSocket?.add(
      jsonEncode({'type': 'media_ready', 'memberId': memberId}),
    );
    await _applyMicrophone(
      _voiceMode == VoiceMode.automatic && !_muted && _canSpeak,
    );
    await _applyAudioBitrate();
    _refreshMembers();
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
    _eventsSocket = socket;
    _eventSubscription = socket.listen(
      _handleManagementEvent,
      onDone: _scheduleEventReconnect,
      onError: (_, _) => _scheduleEventReconnect(),
    );
  }

  Future<void> _handleManagementEvent(dynamic raw) async {
    try {
      final event = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (event['type']) {
        case 'snapshot':
          _applySnapshot(event);
        case 'room_updated':
          _summary = InternetRoomSummary.fromJson(
            event['room'] as Map<String, dynamic>,
          );
          notifyListeners();
        case 'voice_policy':
          if (event['memberId'] == memberId) {
            _canSpeak = event['canSpeak'] as bool? ?? false;
            if (!_canSpeak) await _applyMicrophone(false);
            await _syncBackgroundControls();
          }
          _applyMembers(event['members']);
        case 'role_changed':
          isHost = event['hostMemberId'] == memberId;
          _applyMembers(event['members']);
        case 'room_ended':
          _roomEnded = true;
          _eventReconnectTimer?.cancel();
          _setConnectionState(InternetConnectionState.disconnected);
          AppLog.warn('DawnInternet', '房间已被房主解散或因超时关闭');
        case 'pake_hello':
          if (isHost) await _handlePakeHello(event);
        case 'pake_confirm':
          if (isHost) await _handlePakeConfirm(event);
      }
    } catch (error, stack) {
      AppLog.error('DawnInternet', '管理事件处理失败：$error', stack);
    }
  }

  void _applySnapshot(Map<String, dynamic> event) {
    final room = event['room'];
    if (room is Map<String, dynamic>) {
      _summary = InternetRoomSummary.fromJson(room);
    }
    isHost = event['hostMemberId'] == memberId;
    _canSpeak = event['canSpeak'] as bool? ?? _canSpeak;
    _applyMembers(event['members']);
  }

  void _applyMembers(dynamic raw) {
    if (raw is! List<dynamic>) return;
    _members
      ..clear()
      ..addAll(
        raw.indexed.map((entry) {
          final (index, item) = entry;
          final value = item as Map<String, dynamic>;
          final id = value['id'] as String;
          final sortOrder = value['joinOrder'] as int? ?? index;
          _memberSortOrders[id] = sortOrder;
          return InternetMember(
            id: id,
            nickname: value['nickname'] as String? ?? id,
            isHost: value['isHost'] as bool? ?? false,
            canSpeak: value['canSpeak'] as bool? ?? true,
            // DawnMesh Server emits this array in immutable join order. Older
            // servers do not expose the numeric order, so the array index is
            // the protocol-compatible fallback.
            sortOrder: sortOrder,
            isSpeaking: _speakingIds.contains(id),
          );
        }),
      )
      ..sort(InternetMember.compareStable);
    notifyListeners();
  }

  Future<void> _handlePakeHello(Map<String, dynamic> event) async {
    final scalar = _hostPasswordScalar;
    if (scalar == null || _eventsSocket == null) return;
    final admissionId = event['admissionId'] as String;
    final guestMemberId = event['memberId'] as String;
    final clientMessage = base64Decode(event['body'] as String);
    _hostAdmissions.removeWhere(
      (_, pending) =>
          DateTime.now().difference(pending.created) >
          const Duration(seconds: 30),
    );
    if (clientMessage.length != 65 || _hostAdmissions.length >= 8) return;
    final server = Spake2(isA: false, passwordScalar: scalar);
    final identities = _pakeIdentities(
      profile.instanceId ?? '',
      roomId,
      admissionId,
      guestMemberId,
    );
    final keys = server.finish(
      clientMessage,
      a: identities.$1,
      b: identities.$2,
    );
    _hostAdmissions[admissionId] = _HostAdmission(keys, DateTime.now());
    _eventsSocket!.add(
      jsonEncode({
        'type': 'pake_reply',
        'admissionId': admissionId,
        'body': base64Encode([...server.message, ...keys.confirmB]),
      }),
    );
  }

  Future<void> _handlePakeConfirm(Map<String, dynamic> event) async {
    final socket = _eventsSocket;
    if (socket == null) return;
    final admissionId = event['admissionId'] as String;
    final pending = _hostAdmissions.remove(admissionId);
    final confirm = base64Decode(event['body'] as String);
    if (pending == null || !Spake2Keys.equal(confirm, pending.keys.confirmA)) {
      socket.add(
        jsonEncode({'type': 'admission_rejected', 'admissionId': admissionId}),
      );
      return;
    }
    final cipher = await SessionCipher.fromKey(
      Spake2Keys.hkdf(
        pending.keys.sharedKey,
        'DawnMesh internet room key wrapping v1',
      ),
    );
    final encrypted = await cipher.encrypt(
      _roomKey,
      associatedData: Uint8List.fromList(utf8.encode(admissionId)),
    );
    socket.add(
      jsonEncode({
        'type': 'pake_key',
        'admissionId': admissionId,
        'body': base64Encode([...encrypted.nonce, ...encrypted.ciphertext]),
      }),
    );
  }

  void _scheduleEventReconnect() {
    if (_closed || _roomEnded || _eventReconnectTimer != null) return;
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
    if (_closed || _roomEnded) return;
    _reconnectStartedAt ??= DateTime.now();
    if (DateTime.now().difference(_reconnectStartedAt!) >=
        const Duration(minutes: 10)) {
      _setConnectionState(InternetConnectionState.disconnected);
      return;
    }
    _setConnectionState(InternetConnectionState.reconnecting);
    AppLog.warn('DawnInternet', '媒体连接中断：$reason；尝试恢复');
    Future<void>.delayed(const Duration(seconds: 2), () async {
      if (_closed || _connectionState != InternetConnectionState.reconnecting) {
        return;
      }
      try {
        final grant = await _resume();
        await _listener?.dispose();
        await _livekitRoom?.dispose();
        await _connectLiveKit(grant);
        _reconnectStartedAt = null;
      } catch (error) {
        if (!_closed) {
          _beginFullReconnect('$error');
        }
      }
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
    if (_connectionState == value) return;
    _connectionState = value;
    notifyListeners();
  }

  void _refreshMembers() {
    final room = _livekitRoom;
    if (room == null) return;
    final management = {for (final item in _members) item.id: item};
    final participants = <Participant>[...room.remoteParticipants.values]
      ..sort((a, b) => a.identity.compareTo(b.identity));
    final local = room.localParticipant;
    if (local != null) participants.add(local);
    var nextOrder = _memberSortOrders.values.fold<int>(
      0,
      (value, order) => order >= value ? order + 1 : value,
    );
    _members
      ..clear()
      ..addAll(
        participants.map((participant) {
          final managed = management[participant.identity];
          return InternetMember(
            id: participant.identity,
            nickname: participant.name.isEmpty
                ? (managed?.nickname ?? participant.identity)
                : participant.name,
            isHost:
                managed?.isHost ?? (participant.identity == memberId && isHost),
            canSpeak: managed?.canSpeak ?? participant.permissions.canPublish,
            sortOrder:
                managed?.sortOrder ??
                _memberSortOrders.putIfAbsent(
                  participant.identity,
                  () => nextOrder++,
                ),
            isSpeaking: _speakingIds.contains(participant.identity),
          );
        }),
      )
      ..sort(InternetMember.compareStable);
    notifyListeners();
  }

  void _onDataReceived(DataReceivedEvent event) {
    if (event.topic != 'dawnmesh.chat.v1') return;
    unawaited(_decryptChat(event));
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
      _messages.add(
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
      );
      if (_messages.length > 100) _messages.removeAt(0);
      notifyListeners();
    } catch (error) {
      AppLog.warn('DawnInternet', '忽略无效聊天数据：$error');
    }
  }

  Future<void> sendChat(String text) async {
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
    _messages.add(
      InternetChatMessage(
        id: id,
        senderId: memberId,
        senderName: nickname,
        text: value,
        sentAt: now,
        isMine: true,
      ),
    );
    notifyListeners();
  }

  Future<void> setVoiceMode(VoiceMode value) async {
    if (_voiceMode == value || _closed) return;
    _voiceMode = value;
    _pttPressed = false;
    await _applyMicrophone(
      value == VoiceMode.automatic && !_muted && _canSpeak,
    );
    await _syncBackgroundControls();
    notifyListeners();
  }

  Future<void> setAudioProfile(InternetAudioProfile value) async {
    if (_closed) return;
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
    if (_voiceMode != VoiceMode.pushToTalk || _closed || !_canSpeak || _muted) {
      pressed = false;
    }
    if (_pttPressed == pressed) return;
    _pttPressed = pressed;
    await _applyMicrophone(pressed);
    await _syncBackgroundControls();
    notifyListeners();
  }

  Future<void> toggleMute() async {
    _muted = !_muted;
    if (_muted) _pttPressed = false;
    await _applyMicrophone(
      !_muted &&
          _canSpeak &&
          (_voiceMode == VoiceMode.automatic || _pttPressed),
    );
    await _syncBackgroundControls();
    notifyListeners();
  }

  Future<void> _applyMicrophone(bool enabled) async {
    await _livekitRoom?.localParticipant?.setMicrophoneEnabled(
      enabled && _canSpeak && !_muted,
    );
    if (enabled) await _applyAudioBitrate();
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
    if (_closed) return;
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
      case 'ptt':
        await setPtt(value == true);
      case 'mute':
        if ((value == true) != _muted) await toggleMute();
    }
  }

  Future<void> _syncBackgroundControls() => _backgroundControls.update(
    bluetooth: false,
    internet: true,
    automatic: _voiceMode == VoiceMode.automatic,
    pressed: _pttPressed,
    muted: _muted || !_canSpeak,
  );

  Future<void> renameRoom(String value) =>
      api.renameRoom(roomId, value.trim(), resumeToken);
  Future<void> setMemberCanSpeak(String targetId, bool value) =>
      api.setVoicePolicy(roomId, targetId, value, resumeToken);
  Future<void> transferHost(String targetId) =>
      api.handover(roomId, targetId, resumeToken);

  Future<void> leave({bool endRoom = false}) async {
    if (_closed) return;
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

  Future<void> disposeSession() async {
    if (_closed) return;
    _closed = true;
    _eventReconnectTimer?.cancel();
    await _connectivitySubscription?.cancel();
    await _backgroundControls.close();
    await _eventSubscription?.cancel();
    await _eventsSocket?.close();
    await _listener?.dispose();
    await _livekitRoom?.disconnect();
    await _livekitRoom?.dispose();
    await AudioManager.instance.setAudioSessionManagementMode(
      AudioSessionManagementMode.automatic,
    );
    await _waveController.close();
    _roomKey.fillRange(0, _roomKey.length, 0);
    api.close();
  }
}

class _AdmissionResult {
  const _AdmissionResult(this.grant, this.roomKey, this.passwordScalar);
  final InternetConnectionGrant grant;
  final Uint8List roomKey;
  final BigInt passwordScalar;
}

class _HostAdmission {
  const _HostAdmission(this.keys, this.created);
  final Spake2Keys keys;
  final DateTime created;
}
