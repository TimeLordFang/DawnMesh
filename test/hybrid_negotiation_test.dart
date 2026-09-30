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

class _Sender extends Fake implements rtc.RTCRtpSender {
  rtc.MediaStreamTrack? source;
  @override
  Future<void> replaceTrack(rtc.MediaStreamTrack? track) async {
    source = track;
  }
}

class _Channel extends Fake implements rtc.RTCDataChannel {
  @override
  String get label => 'dawnmesh.direct.v1';
  @override
  rtc.RTCDataChannelState? state;
  @override
  Function(rtc.RTCDataChannelMessage)? onMessage;
  final sent = <String>[];
  @override
  Future<void> send(rtc.RTCDataChannelMessage message) async {
    sent.add(message.text);
  }

  @override
  Future<void> close() async {
    state = rtc.RTCDataChannelState.RTCDataChannelClosed;
  }
}

class _Track extends Fake implements rtc.MediaStreamTrack {
  _Track(this.id);
  @override
  final String id;
  @override
  String get kind => 'audio';
  @override
  bool enabled = false;
}

class _Local extends Fake implements LocalAudioTrack {
  @override
  final mediaStreamTrack = _Track('mic');
  @override
  bool muted = false;
}

class _Transceiver extends Fake implements rtc.RTCRtpTransceiver {
  _Transceiver(this.sender);
  @override
  final rtc.RTCRtpSender sender;
}

class _Connection extends Fake implements rtc.RTCPeerConnection {
  final channel = _Channel();
  final sender = _Sender();
  bool closed = false;
  int packets = 0;
  bool silence = false;
  @override
  Function(rtc.RTCDataChannel)? onDataChannel;
  @override
  Future<rtc.RTCDataChannel> createDataChannel(
    String label,
    rtc.RTCDataChannelInit init,
  ) async => channel;
  @override
  Future<List<rtc.StatsReport>> getStats([rtc.MediaStreamTrack? track]) async =>
      [
        rtc.StatsReport('pair', 'candidate-pair', 0, {
          'state': 'succeeded',
          'nominated': true,
          'currentRoundTripTime': .02,
        }),
        rtc.StatsReport('audio', 'inbound-rtp', 0, {
          'kind': 'audio',
          'packetsReceived': silence ? packets : ++packets,
          'packetsLost': 0,
          'jitter': .003,
        }),
      ];
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
  }) async => _Transceiver(sender);
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
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  test(
    'three members retain direct audio, PTT and control with no public room',
    () async {
      Room? room = _Room();
      final members = {'y', 'z'};
      final pcs = <_Connection>[];
      final local = _Local();
      final volumes = <String, double>{};
      var publicSends = 0;
      var allowed = true;
      final hybrid = HybridAudio(
        selfId: 'a',
        room: room,
        roomProvider: () => room,
        knownMember: members.contains,
        localTrack: () => local,
        canSend: () => allowed,
        signal: (_, _) async {
          publicSends++;
        },
        canReceive: (_) => allowed,
        changed: () {},
        features: const InternetFeatures(),
        setVolume: (track, volume) async {
          volumes[track.id!] = volume;
        },
        createConnection: (_) async {
          final pc = _Connection();
          pcs.add(pc);
          return pc;
        },
      );
      addTearDown(hybrid.close);
      for (final id in members) {
        await hybrid.receive(id, {'kind': 'hello'});
        final pc = pcs.last;
        pc.connectionState =
            rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected;
        pc.onTrack!(rtc.RTCTrackEvent(track: _Track(id), streams: []));
        pc.channel.state = rtc.RTCDataChannelState.RTCDataChannelOpen;
      }
      await hybrid.setSending(true);
      for (var i = 0; i < 3; i++) {
        await hybrid.pollForTesting();
      }
      expect(hybrid.directCount, 2);
      expect(
        pcs.map((p) => p.sender.source),
        everyElement(same(local.mediaStreamTrack)),
      );
      // SFU disposal removes both roster and track publications entirely.
      room = null;
      hybrid.cloudAvailable = false;
      final sentBefore = publicSends;
      for (final pc in pcs) {
        pc.silence = true;
      }
      for (var i = 0; i < 7; i++) {
        await hybrid.pollForTesting();
      }
      expect(hybrid.connectedCount, 2);
      expect(
        hybrid.directCount,
        2,
      ); // DTX silence must not mute the next utterance.
      expect(volumes, {'y': 1, 'z': 1});
      expect(publicSends, sentBefore);
      expect(
        pcs.every((pc) => pc.channel.sent.any((s) => s.contains('hello'))),
        isTrue,
      );
      await hybrid.setSending(false);
      expect(pcs.map((p) => p.sender.source), everyElement(isNull));
      await hybrid.setSending(true);
      expect(
        pcs.map((p) => p.sender.source),
        everyElement(same(local.mediaStreamTrack)),
      );
      // One user's departure cannot tear down the other user's direct audio.
      pcs.first.channel.onMessage!(rtc.RTCDataChannelMessage('{"kind":"bye"}'));
      await hybrid.pollForTesting();
      expect(pcs.first.closed, isTrue);
      expect(pcs.last.closed, isFalse);
      expect(hybrid.directCount, 1);
      allowed = false;
      await hybrid.pollForTesting();
      expect(hybrid.directCount, 0);
      expect(pcs.last.sender.source, isNull);
      expect(volumes['z'], 0);
      await hybrid.receive('stranger', {'kind': 'hello'});
      expect(pcs.length, 2);
    },
  );
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
    expect(hybrid.status, '直连已连接 1 · 等待直连语音验证');
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
