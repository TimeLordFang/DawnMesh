import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

import '../diagnostics/app_log.dart';
import '../transport/wifi_direct_credentials.dart';
import '../transport/wifi_direct_manager.dart';
import 'internet_features.dart';
import 'exclusive_audio_switch.dart';
import 'hybrid_wifi_link.dart';
import 'hybrid_ice.dart';
import 'hybrid_probe.dart';

/// One capture, two transports, one audible receiver per member. SFU remains
/// subscribed as a warm fallback. Direct RTP uses DTLS-SRTP; its SDP fingerprints
/// travel in the room's authenticated encrypted signaling envelope.
class HybridAudio {
  HybridAudio({
    required this.selfId,
    required this.room,
    required this.signal,
    required this.canReceive,
    required this.changed,
    required this.features,
    this.roomProvider,
    this.localTrack,
    this.knownMember,
    this.canSend,
    this.ended,
    Future<void> Function(rtc.MediaStreamTrack, double)? setVolume,
    Future<rtc.RTCPeerConnection> Function(Map<String, dynamic>)?
    createConnection,
  }) : _createConnection = createConnection ?? rtc.createPeerConnection,
       _setVolume =
           setVolume ??
           ((track, volume) => rtc.Helper.setVolume(volume, track));
  final Future<rtc.RTCPeerConnection> Function(Map<String, dynamic>)
  _createConnection;
  final String selfId;
  final Room room;
  final Room? Function()? roomProvider;
  final LocalAudioTrack? Function()? localTrack;
  final bool Function(String)? knownMember;
  final bool Function()? canSend;
  final void Function()? ended;
  final Future<void> Function(rtc.MediaStreamTrack, double) _setVolume;
  Room? get currentRoom => roomProvider == null ? room : roomProvider!();
  bool cloudAvailable = true;
  String? _hostId;
  bool _known(String id) =>
      knownMember?.call(id) ??
      currentRoom?.remoteParticipants.containsKey(id) ??
      false;
  Set<String> get connectedIds => _peers.values
      .where(
        (p) =>
            p.pc.connectionState ==
            rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected,
      )
      .map((p) => p.id)
      .toSet();
  final Future<void> Function(String? to, Map<String, dynamic> data) signal;
  final bool Function(String id) canReceive;
  final void Function() changed;
  InternetFeatures features;
  final Map<String, _DirectPeer> _peers = {};
  final _ice = HybridIceInbox();
  final Map<String, DateTime> _available = {};
  Future<void> _queue = Future<void>.value();
  Timer? _timer;
  bool _closed = false;
  bool _sending = false;
  HybridWifiLink? _wifi;
  int _tickCount = 0;
  bool _tickPending = false;
  void cloudTrackChanged(String id) {
    final peer = _peers[id];
    if (peer == null) return;
    peer.remote?.enabled = false;
    unawaited(_select(peer, false));
  }

  int get directCount => _peers.values.where((p) => p.audible).length;
  int get connectedCount => _peers.values
      .where(
        (p) =>
            p.pc.connectionState ==
            rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected,
      )
      .length;
  String get status => connectedCount > 0
      ? '直连已连接 $connectedCount · ${directCount > 0 ? '已选直连 $directCount 路' : _peers.values.where((p) => connectedIds.contains(p.id)).first.status}'
      : _wifi?.status ?? '正在协商直连语音';

  Future<void> start({
    required String hostId,
    required Uint8List roomKey,
  }) async {
    _hostId = hostId;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_tickPending || _closed) return;
      _tickPending = true;
      _enqueue(() async {
        try {
          await _tick();
        } finally {
          _tickPending = false;
        }
      });
    });
    final hash = sha256.convert([
      ...utf8.encode('DawnMesh hybrid v2:$hostId'),
      ...roomKey,
    ]).toString();
    final manager = WifiDirectManager.instance;
    _wifi = HybridWifiLink(
      selfId: selfId,
      hostId: hostId,
      credentials: WifiDirectCredentials(
        networkName:
            'DIRECT-${hash.substring(0, 2)}-DM-${hash.substring(2, 10)}',
        passphrase: hash.substring(10, 34),
      ),
      signal: (data) => _signal(null, data),
      info: manager.getConnectionInfo,
      availability: manager.hybridAvailability,
      changed: changed,
      create: manager.createGroup,
      join: manager.connectKnownGroup,
      disconnect: () async {
        await manager.disconnect();
        return manager.removeGroup();
      },
    )..start();
    await _signal(null, {'kind': 'hello'});
  }

  void _attachControl(_DirectPeer peer, rtc.RTCDataChannel channel) {
    if (channel.label != 'dawnmesh.direct.v1' || peer.control != null) {
      unawaited(channel.close());
      return;
    }
    peer.control = channel;
    channel.onMessage = (message) {
      if (_closed || message.isBinary || message.text.length > 14000) return;
      try {
        final data = jsonDecode(message.text);
        if (data is Map<String, dynamic>) unawaited(receive(peer.id, data));
      } catch (_) {}
    };
  }

  Future<void> _signal(String? to, Map<String, dynamic> data) async {
    var delivered = false;
    for (final peer in _peers.values.toList()) {
      if (to != null && peer.id != to) continue;
      final channel = peer.control;
      if (channel?.state != rtc.RTCDataChannelState.RTCDataChannelOpen) {
        continue;
      }
      try {
        await channel!.send(rtc.RTCDataChannelMessage(jsonEncode(data)));
        delivered = true;
      } catch (_) {}
    }
    if (cloudAvailable && (!delivered || to == null)) {
      try {
        await signal(to, data).timeout(const Duration(seconds: 1));
      } catch (error) {
        AppLog.debug('Hybrid', '公网信令暂不可用，保留已有直连：$error');
      }
    }
  }

  Future<void> announceEnd() => _signal(null, {'kind': 'room_ended'});

  /// Uses the same serialized sampler as the periodic task.
  Future<void> pollForTesting() {
    _enqueue(_tick);
    return _queue;
  }

  void _enqueue(Future<void> Function() work) {
    _queue = _queue
        .then((_) async {
          if (!_closed) await work();
        })
        .catchError((Object error) {
          AppLog.warn('Hybrid', '直连任务失败，保留公网：$error');
        });
  }

  Future<void> receive(String from, Map<String, dynamic> data) {
    _enqueue(() async {
      if (!_known(from)) return;
      final kind = data['kind'];
      if (kind == 'wifi_ready') {
        _wifi?.receive(from, data);
        return;
      }
      if (kind == 'hello') {
        _available[from] = DateTime.now();
        if (!_peers.containsKey(from) &&
            selfId.compareTo(from) < 0 &&
            _peers.length < features.maxPeers) {
          final peer = await _create(from, _randomSession());
          await _description(peer, await peer.pc.createOffer());
        }
        return;
      }
      if (kind == 'room_ended' && from == _hostId) {
        ended?.call();
        return;
      }
      if (kind == 'bye') {
        _available.remove(from);
        await _remove(from);
        return;
      }
      final session = data['session'];
      if (session is String && kind == 'candidate') {
        final peer = _peers[from];
        if (peer != null && peer.session != session) return;
        await _ice.receive(from, session, data);
        return;
      }
      final sdp = data['sdp'];
      if (session is! String ||
          session.length > 64 ||
          sdp is! String ||
          sdp.length > 12000) {
        return;
      }
      if (kind == 'offer' && from.compareTo(selfId) < 0) {
        if (_peers[from]?.session == session) return;
        if (!_peers.containsKey(from) && _peers.length >= features.maxPeers) {
          return;
        }
        await _remove(from);
        final peer = await _create(from, session);
        await peer.pc.setRemoteDescription(
          rtc.RTCSessionDescription(privateCandidatesOnly(sdp), 'offer'),
        );
        await _ice.activate(from, session, peer.pc.addCandidate);
        await _description(peer, await peer.pc.createAnswer());
      } else if (kind == 'answer') {
        final peer = _peers[from];
        if (peer == null || peer.session != session) return;
        await peer.pc.setRemoteDescription(
          rtc.RTCSessionDescription(privateCandidatesOnly(sdp), 'answer'),
        );
        await _ice.activate(from, session, peer.pc.addCandidate);
      }
    });

    return _queue;
  }

  static String _randomSession() => base64UrlEncode(
    List<int>.generate(18, (_) => Random.secure().nextInt(256)),
  );

  Future<_DirectPeer> _create(String id, String session) async {
    final pc = await _createConnection({
      'iceServers': <Object>[],
      'sdpSemantics': 'unified-plan',
      'continualGatheringPolicy': 'gather_continually',
    });
    final peer = _DirectPeer(id, session, pc);
    _peers[id] = peer;
    pc.onDataChannel = (channel) => _attachControl(peer, channel);
    if (selfId.compareTo(id) < 0) {
      _attachControl(
        peer,
        await pc.createDataChannel(
          'dawnmesh.direct.v1',
          rtc.RTCDataChannelInit()..ordered = true,
        ),
      );
    }
    pc.onIceCandidate = (candidate) {
      final value = candidate.candidate;
      if (value == null || !isPrivateHostCandidate(value)) return;
      _enqueue(() async {
        if (!identical(_peers[id], peer)) return;
        await _signal(id, {
          'kind': 'candidate',
          'session': session,
          'candidate': value,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      });
    };
    pc.onIceGatheringState = (state) {
      if (state == rtc.RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !peer.gathered.isCompleted) {
        peer.gathered.complete();
      }
    };
    pc.onTrack = (event) {
      if (event.track.kind != 'audio') return;
      // onTrack is emitted by remote SDP, before ICE/DTLS completes.
      event.track.enabled = false;
      peer.remote = event.track;
      _enqueue(() => _select(peer, false));
    };
    pc.onConnectionState = (state) {
      AppLog.info('Hybrid', '直连语音连接状态：$state');
      if (!_closed) changed();
      if (state != rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _enqueue(() => _select(peer, false));
      }
    };
    final transceiver = await pc.addTransceiver(
      kind: rtc.RTCRtpMediaType.RTCRtpMediaTypeAudio,
      init: rtc.RTCRtpTransceiverInit(
        direction: rtc.TransceiverDirection.SendRecv,
      ),
    );
    peer.sender = transceiver.sender;
    await _updateSender(peer);
    return peer;
  }

  Future<void> _description(
    _DirectPeer peer,
    rtc.RTCSessionDescription description,
  ) async {
    await peer.pc.setLocalDescription(description);
    await peer.gathered.future.timeout(
      const Duration(milliseconds: 800),
      onTimeout: () {},
    );
    if (_closed) return;
    final local = await peer.pc.getLocalDescription();
    await _signal(peer.id, {
      'kind': description.type,
      'session': peer.session,
      'sdp': privateCandidatesOnly(local?.sdp ?? description.sdp ?? ''),
    });
  }

  /// Direct means a local/private host candidate, never another Internet relay.
  static String privateCandidatesOnly(String sdp) => sdp
      .split('\r\n')
      .where((line) {
        if (line == 'a=end-of-candidates') return false;
        if (!line.startsWith('a=candidate:')) return true;
        return isPrivateHostCandidate(line);
      })
      .join('\r\n');

  Future<void> setSending(bool enabled) async {
    _sending = enabled;
    _enqueue(() async {
      for (final peer in _peers.values) {
        await _updateSender(peer);
      }
    });
    await _queue;
  }

  Future<void> _updateSender(_DirectPeer peer) async {
    final local =
        localTrack?.call() ??
        currentRoom?.localParticipant
            ?.getTrackPublicationBySource(TrackSource.microphone)
            ?.track;
    final track =
        _sending &&
            (canSend?.call() ?? true) &&
            local is LocalAudioTrack &&
            !local.muted
        ? local.mediaStreamTrack
        : null;
    if (peer.sourceId == track?.id) return;
    await peer.sender?.replaceTrack(track);
    peer.sourceId = track?.id;
  }

  Future<void> _tick() async {
    while (_peers.length > features.maxPeers) {
      await _remove(_peers.keys.last);
    }
    if (_tickCount++ % 5 == 0) await _signal(null, {'kind': 'hello'});
    for (final peer in _peers.values.toList()) {
      try {
        if (!_known(peer.id)) {
          await _remove(peer.id);
          continue;
        }
        await _updateSender(peer);
        final connected =
            peer.pc.connectionState ==
            rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected;
        if (connected) {
          peer.disconnectedSince = null;
        } else {
          peer.disconnectedSince ??= DateTime.now();
        }
        if (!connected &&
            cloudAvailable &&
            DateTime.now().difference(peer.disconnectedSince!).inSeconds > 12) {
          await _remove(peer.id);
          continue;
        }
        final probe = peer.probe.sample(await peer.pc.getStats());
        final use = peer.policy.update(
          connected: connected && canReceive(peer.id),
          rttMs: probe.rttMs,
          loss: probe.loss,
          jitterMs: probe.jitterMs,
          features: features,
        );
        peer.status = !canReceive(peer.id)
            ? '发言权限待同步'
            : probe.rttMs == null
            ? '等待直连质量数据'
            : probe.rttMs! > features.maxRttMs ||
                  probe.loss > features.maxLossPercent / 100 ||
                  probe.jitterMs > features.maxJitterMs
            ? (cloudAvailable ? '直连质量不足，使用公网' : '直连质量不足，正在重试')
            : !use
            ? '正在确认直连稳定性'
            : !probe.audioFlow
            ? '直连就绪，等待对方讲话'
            : '直连语音中';
        // Warm the route with ICE probes even while both users are silent.
        // Keep the healthy route open during DTX silence so the next utterance
        // is audible immediately. With no SFU, retain even a degraded direct path.
        await _select(
          peer,
          use || (!cloudAvailable && connected && canReceive(peer.id)),
        );
      } catch (error) {
        await _select(peer, false);
        AppLog.warn('Hybrid', '直连探测异常，回退公网：$error');
      }
    }
    changed();
  }

  /// Await muting the old native track BEFORE enabling the new one. A brief
  /// gap is preferable to double audio. Also handles SFU resubscription tracks.
  Future<void> _select(_DirectPeer peer, bool direct) {
    final task = peer.selection.then((_) => _applySelection(peer, direct));
    peer.selection = task.catchError((Object error) {
      peer.remote?.enabled = false;
      peer.audible = false;
      AppLog.warn('Hybrid', '音频切换失败，关闭直连播放：$error');
    });
    return task;
  }

  Future<void> _applySelection(_DirectPeer peer, bool direct) async {
    final cloud = currentRoom
        ?.remoteParticipants[peer.id]
        ?.audioTrackPublications
        .firstOrNull
        ?.track;
    final remote = peer.remote;
    direct = direct && remote != null && !_closed && canReceive(peer.id);
    await switchExclusiveAudio(
      direct: direct,
      cloudPlayback: (enabled) async {
        if (cloud != null) {
          await _setVolume(cloud.mediaStreamTrack, enabled ? 1 : 0);
        }
      },
      directPlayback: (enabled) async {
        if (remote == null) return;
        if (enabled) remote.enabled = true;
        await _setVolume(remote, enabled ? 1 : 0);
        if (!enabled) remote.enabled = false;
      },
    );
    peer.audible = direct;
    peer.watchdog?.cancel();
    if (direct) {
      peer.watchdog = Timer(const Duration(milliseconds: 1800), () {
        peer.remote?.enabled = false;
        unawaited(_select(peer, false).catchError((Object _) {}));
      });
    }
  }

  Future<void> _remove(String id) async {
    final peer = _peers.remove(id);
    if (peer == null) return;
    _ice.forget(id);
    try {
      await _select(peer, false);
    } finally {
      peer.watchdog?.cancel();
      await peer.control?.close();
      await peer.pc.close();
      await peer.pc.dispose();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    await _queue;
    await _signal(null, {'kind': 'bye'});
    for (final id in _peers.keys.toList()) {
      try {
        await _remove(id);
      } catch (error) {
        AppLog.warn('Hybrid', '关闭直连音轨失败：$error');
      }
    }
    _ice.clear();
    await _wifi?.close();
  }
}

class _DirectPeer {
  _DirectPeer(this.id, this.session, this.pc);
  final String id, session;
  final rtc.RTCPeerConnection pc;
  DateTime? disconnectedSince;
  final gathered = Completer<void>();
  final policy = HybridRoutePolicy();
  final probe = HybridProbeSampler();
  String status = '等待直连语音验证';
  rtc.RTCDataChannel? control;
  rtc.RTCRtpSender? sender;
  rtc.MediaStreamTrack? remote;
  String? sourceId;
  bool audible = false;
  Future<void> selection = Future<void>.value();
  Timer? watchdog;
}
