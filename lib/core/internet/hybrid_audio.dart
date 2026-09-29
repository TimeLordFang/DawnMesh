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
  });
  final String selfId;
  final Room room;
  final Future<void> Function(String? to, Map<String, dynamic> data) signal;
  final bool Function(String id) canReceive;
  final void Function() changed;
  InternetFeatures features;
  final Map<String, _DirectPeer> _peers = {};
  final Map<String, DateTime> _available = {};
  Future<void> _queue = Future<void>.value();
  Timer? _timer;
  bool _closed = false;
  bool _sending = false;
  bool _ownsWifiGroup = false;
  Future<void>? _wifiSetup;
  int _tickCount = 0;
  bool _tickPending = false;
  void cloudTrackChanged(String id) {
    final peer = _peers[id];
    if (peer == null) return;
    peer.remote?.enabled = false;
    unawaited(_select(peer, false));
  }

  int get directCount => _peers.values.where((p) => p.audible).length;

  Future<void> start({required bool isHost, required Uint8List roomKey}) async {
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
    // Group formation is optional: devices on the same LAN can connect too.
    // Never bind the whole process to P2P: the SFU must retain Internet access.
    _wifiSetup = _setupWifi(isHost, roomKey);
    await signal(null, {'kind': 'hello'});
  }

  Future<void> _setupWifi(bool host, Uint8List key) async {
    final wifi = WifiDirectManager.instance;
    try {
      if ((await wifi.getConnectionInfo()).groupFormed || _closed) return;
      final hash = sha256.convert([
        ...utf8.encode('DawnMesh hybrid v1'),
        ...key,
      ]).toString();
      final credentials = WifiDirectCredentials(
        networkName:
            'DIRECT-${hash.substring(0, 2)}-DM-${hash.substring(2, 10)}',
        passphrase: hash.substring(10, 34),
      );
      _ownsWifiGroup = host
          ? await wifi.createGroup(credentials)
          : await wifi.connectKnownGroup(credentials);
      if (_closed && _ownsWifiGroup) {
        await wifi.disconnect();
        _ownsWifiGroup = false;
      }
    } catch (error) {
      AppLog.warn('Hybrid', 'Wi-Fi Direct 不可用，保留公网：$error');
    }
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

  void receive(String from, Map<String, dynamic> data) => _enqueue(() async {
    if (!room.remoteParticipants.containsKey(from)) return;
    final kind = data['kind'];
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
    if (kind == 'bye') {
      _available.remove(from);
      await _remove(from);
      return;
    }
    final session = data['session'];
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
      await _description(peer, await peer.pc.createAnswer());
    } else if (kind == 'answer') {
      final peer = _peers[from];
      if (peer == null || peer.session != session) return;
      await peer.pc.setRemoteDescription(
        rtc.RTCSessionDescription(privateCandidatesOnly(sdp), 'answer'),
      );
    }
  });

  static String _randomSession() => base64UrlEncode(
    List<int>.generate(18, (_) => Random.secure().nextInt(256)),
  );

  Future<_DirectPeer> _create(String id, String session) async {
    final pc = await rtc.createPeerConnection({
      'iceServers': <Object>[],
      'sdpSemantics': 'unified-plan',
    });
    final peer = _DirectPeer(id, session, pc);
    _peers[id] = peer;
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
    await signal(peer.id, {
      'kind': description.type,
      'session': peer.session,
      'sdp': privateCandidatesOnly(local?.sdp ?? description.sdp ?? ''),
    });
  }

  /// Direct means a local/private host candidate, never another Internet relay.
  static String privateCandidatesOnly(String sdp) => sdp
      .split('\r\n')
      .where((line) {
        if (!line.startsWith('a=candidate:')) return true;
        final parts = line.split(' ');
        if (parts.length < 8 || parts[6] != 'typ' || parts[7] != 'host') {
          return false;
        }
        final ip = parts[4].toLowerCase();
        final octets = ip.split('.').map(int.tryParse).toList();
        return (octets.length == 4 &&
                octets.every((n) => n != null && n >= 0 && n <= 255) &&
                (octets[0] == 10 ||
                    (octets[0] == 192 && octets[1] == 168) ||
                    (octets[0] == 172 &&
                        octets[1]! >= 16 &&
                        octets[1]! <= 31))) ||
            ip.startsWith('fc') && ip.contains(':') ||
            ip.startsWith('fd') && ip.contains(':') ||
            ip.startsWith('fe80:');
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
    final local = room.localParticipant
        ?.getTrackPublicationBySource(TrackSource.microphone)
        ?.track;
    final track = _sending && local is LocalAudioTrack && !local.muted
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
    if (_tickCount++ % 5 == 0) await signal(null, {'kind': 'hello'});
    for (final peer in _peers.values.toList()) {
      try {
        if (!room.remoteParticipants.containsKey(peer.id) ||
            DateTime.now()
                    .difference(_available[peer.id] ?? peer.created)
                    .inSeconds >
                16) {
          await _remove(peer.id);
          continue;
        }
        await _updateSender(peer);
        final connected =
            peer.pc.connectionState ==
            rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected;
        if (!connected &&
            DateTime.now().difference(peer.created).inSeconds > 12) {
          await _remove(peer.id);
          continue;
        }
        final stats = await peer.pc.getStats();
        double? rtt;
        double jitter = 0, loss = 0;
        bool audioFlow = false;
        for (final stat in stats) {
          final v = stat.values;
          if (stat.type == 'candidate-pair' &&
              v['state'] == 'succeeded' &&
              v['nominated'] == true) {
            final seconds = v['currentRoundTripTime'];
            if (seconds is num) rtt = seconds.toDouble() * 1000;
          }
          if (stat.type == 'inbound-rtp' &&
              (v['kind'] == 'audio' || v['mediaType'] == 'audio')) {
            jitter = ((v['jitter'] as num?)?.toDouble() ?? 0) * 1000;
            final received = (v['packetsReceived'] as num?)?.toInt() ?? 0;
            final lost = (v['packetsLost'] as num?)?.toInt() ?? 0;
            final delta = received - peer.received;
            final missing = max(0, lost - peer.lost);
            audioFlow = delta > 0;
            loss = delta + missing > 0 ? missing / (delta + missing) : 0;
            peer.received = received;
            peer.lost = lost;
          }
        }
        final cloud = room
            .remoteParticipants[peer.id]
            ?.audioTrackPublications
            .firstOrNull
            ?.track;
        double? cloudRtt;
        if (cloud != null) {
          for (final stat
              in await cloud.receiver?.getStats() ?? <rtc.StatsReport>[]) {
            if (stat.type == 'candidate-pair' &&
                stat.values['state'] == 'succeeded' &&
                stat.values['nominated'] == true) {
              cloudRtt = (stat.values['currentRoundTripTime'] as num?)
                  ?.toDouble();
              if (cloudRtt != null) cloudRtt *= 1000;
            }
          }
        }
        final use = peer.policy.update(
          connected: connected && audioFlow && canReceive(peer.id),
          rttMs: rtt,
          cloudRttMs: cloudRtt,
          loss: loss,
          jitterMs: jitter,
          features: features,
        );
        await _select(peer, use);
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
    final cloud = room
        .remoteParticipants[peer.id]
        ?.audioTrackPublications
        .firstOrNull
        ?.track;
    final remote = peer.remote;
    direct =
        direct &&
        remote != null &&
        cloud != null &&
        !_closed &&
        canReceive(peer.id);
    await switchExclusiveAudio(
      direct: direct,
      cloudPlayback: (enabled) async {
        if (cloud != null) {
          await rtc.Helper.setVolume(enabled ? 1 : 0, cloud.mediaStreamTrack);
        }
      },
      directPlayback: (enabled) async {
        if (remote == null) return;
        if (enabled) remote.enabled = true;
        await rtc.Helper.setVolume(enabled ? 1 : 0, remote);
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
    try {
      await _select(peer, false);
    } finally {
      peer.watchdog?.cancel();
      await peer.pc.close();
      await peer.pc.dispose();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    await _queue;
    for (final id in _peers.keys.toList()) {
      try {
        await _remove(id);
      } catch (error) {
        AppLog.warn('Hybrid', '关闭直连音轨失败：$error');
      }
    }
    await _wifiSetup;
    if (_ownsWifiGroup) {
      await WifiDirectManager.instance.disconnect();
      _ownsWifiGroup = false;
    }
    try {
      await signal(null, {'kind': 'bye'});
    } catch (_) {}
  }
}

class _DirectPeer {
  _DirectPeer(this.id, this.session, this.pc);
  final String id, session;
  final rtc.RTCPeerConnection pc;
  final created = DateTime.now();
  final gathered = Completer<void>();
  final policy = HybridRoutePolicy();
  rtc.RTCRtpSender? sender;
  rtc.MediaStreamTrack? remote;
  String? sourceId;
  int received = 0, lost = 0;
  bool audible = false;
  Future<void> selection = Future<void>.value();
  Timer? watchdog;
}
