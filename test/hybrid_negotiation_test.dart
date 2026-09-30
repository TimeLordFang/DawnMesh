import 'dart:collection';

import 'package:dawn_mesh/core/internet/hybrid_audio.dart';
import 'package:dawn_mesh/core/internet/internet_features.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

class _Room extends Fake implements Room {
  @override
  UnmodifiableMapView<String, RemoteParticipant> get remoteParticipants =>
      UnmodifiableMapView({'z': _Remote()});
  @override
  LocalParticipant? get localParticipant => null;
}

class _Remote extends Fake implements RemoteParticipant {
  @override
  List<RemoteTrackPublication<RemoteAudioTrack>> get audioTrackPublications =>
      [];
}

class _Sender extends Fake implements rtc.RTCRtpSender {}

class _Transceiver extends Fake implements rtc.RTCRtpTransceiver {
  @override
  rtc.RTCRtpSender get sender => _Sender();
}

class _Connection extends Fake implements rtc.RTCPeerConnection {
  @override
  Function(rtc.RTCIceCandidate)? onIceCandidate;
  @override
  Function(rtc.RTCIceGatheringState)? onIceGatheringState;
  @override
  Function(rtc.RTCTrackEvent)? onTrack;
  @override
  Function(rtc.RTCPeerConnectionState)? onConnectionState;
  @override
  rtc.RTCPeerConnectionState? connectionState;
  rtc.RTCSessionDescription? local;
  bool remoteReady = false;
  final added = <rtc.RTCIceCandidate>[];
  @override
  Future<rtc.RTCRtpTransceiver> addTransceiver({
    rtc.MediaStreamTrack? track,
    rtc.RTCRtpMediaType? kind,
    rtc.RTCRtpTransceiverInit? init,
  }) async => _Transceiver();
  @override
  Future<rtc.RTCSessionDescription> createOffer([
    Map<String, dynamic>? constraints,
  ]) async => rtc.RTCSessionDescription('v=0\r\n', 'offer');
  @override
  Future<void> setLocalDescription(
    rtc.RTCSessionDescription description,
  ) async {
    local = description;
    onIceGatheringState?.call(
      rtc.RTCIceGatheringState.RTCIceGatheringStateComplete,
    );
  }

  @override
  Future<rtc.RTCSessionDescription?> getLocalDescription() async => local;
  @override
  Future<void> setRemoteDescription(
    rtc.RTCSessionDescription description,
  ) async {
    remoteReady = true;
  }

  @override
  Future<void> addCandidate(rtc.RTCIceCandidate candidate) async {
    expect(remoteReady, isTrue);
    added.add(candidate);
  }

  @override
  Future<void> close() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  test('real negotiation sends late ICE, buffers pre-answer ICE and reports idle connected peers', () async {
    final pc = _Connection();
    final signals = <Map<String, dynamic>>[];
    final hybrid = HybridAudio(
      selfId: 'a',
      room: _Room(),
      signal: (_, data) async => signals.add(data),
      canReceive: (_) => true,
      changed: () {},
      features: const InternetFeatures(),
      createConnection: (config) async {
        expect(config['continualGatheringPolicy'], 'gather_continually');
        expect(config['iceServers'], isEmpty);
        return pc;
      },
    );
    addTearDown(hybrid.close);
    await hybrid.receive('z', {'kind': 'hello'});
    final session = signals.single['session'];
    pc.onIceCandidate!(
      rtc.RTCIceCandidate(
        'candidate:1 1 udp 1 192.168.49.1 1234 typ host',
        '0',
        0,
      ),
    );
    await hybrid.receive('z', {
      'kind': 'hello',
    }); // Drain the real signal queue.
    expect(signals.last['kind'], 'candidate');
    expect(signals.last['session'], session);
    await hybrid.receive('z', {
      'kind': 'candidate',
      'session': session,
      'candidate': 'candidate:2 1 udp 1 192.168.49.2 5678 typ host',
      'sdpMid': '0',
      'sdpMLineIndex': 0,
    });
    expect(pc.added, isEmpty);
    await hybrid.receive('z', {
      'kind': 'answer',
      'session': session,
      'sdp': 'v=0\r\n',
    });
    expect(pc.added, hasLength(1));
    pc.connectionState =
        rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected;
    expect(hybrid.connectedCount, 1);
    expect(hybrid.directCount, 0);
    expect(hybrid.status, '直连已连接 1 · 当前使用公网');
    await hybrid.receive('z', {
      'kind': 'candidate',
      'session': 'stale',
      'candidate': 'candidate:3 1 udp 1 192.168.49.3 5678 typ host',
      'sdpMid': '0',
      'sdpMLineIndex': 0,
    });
    expect(pc.added, hasLength(1));
  });
}
