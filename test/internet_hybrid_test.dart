import 'package:dawn_mesh/core/internet/hybrid_audio.dart';
import 'package:dawn_mesh/core/internet/internet_features.dart';
import 'package:dawn_mesh/core/internet/internet_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('old servers and unknown schemas cannot enable native capabilities', () {
    expect(
      InternetServerInfo.fromJson({'instanceId': 'old'}).features.hybridAudio,
      isFalse,
    );
    expect(
      InternetFeatures.fromJson({'schemaVersion': 2, 'hybridAudio': true})
          .hybridAudio,
      isFalse,
    );
    final valid = InternetFeatures.fromJson({
      'schemaVersion': 1,
      'hybridAudio': true,
      'hybridMaxPeers': 100,
      'hybridMaxRttMs': -1,
    });
    expect(valid.hybridAudio, isTrue);
    expect(valid.maxPeers, 4);
    expect(valid.maxRttMs, 120);
  });
  test(
    'direct route requires stable quality, fails back immediately, rewarms',
    () {
      final policy = HybridRoutePolicy();
      bool sample({bool up = true, double? rtt = 30, double loss = 0}) =>
          policy.update(
            connected: up,
            rttMs: rtt,
            loss: loss,
            jitterMs: 5,
            features: const InternetFeatures(),
          );
      expect(sample(), isFalse);
      expect(sample(), isFalse);
      expect(sample(), isTrue);
      expect(sample(loss: .04), isFalse);
      expect(sample(), isFalse);
      expect(sample(), isFalse);
      expect(sample(), isTrue);
      expect(sample(up: false), isFalse);
      expect(sample(), isFalse);
      expect(sample(), isFalse);
      expect(sample(), isTrue);
      expect(sample(rtt: null), isFalse);
      expect(sample(rtt: double.nan), isFalse);
    },
  );
  test('quality thresholds can change without an APK update', () {
    final relaxed = InternetFeatures.fromJson({
      'schemaVersion': 1,
      'hybridMaxLossPercent': 8,
      'hybridMaxJitterMs': 70,
    });
    final policy = HybridRoutePolicy();
    bool sample(InternetFeatures f) => policy.update(
      connected: true,
      rttMs: 50,
      loss: .05,
      jitterMs: 50,
      features: f,
    );
    expect(sample(const InternetFeatures()), isFalse);
    expect(sample(relaxed), isFalse);
    expect(sample(relaxed), isFalse);
    expect(sample(relaxed), isTrue);
    expect(sample(const InternetFeatures()), isFalse);
    final invalid = InternetFeatures.fromJson({
      'schemaVersion': 1,
      'hybridMaxLossPercent': -1,
      'hybridMaxJitterMs': 1000,
    });
    expect(invalid.maxLossPercent, 3);
    expect(invalid.maxJitterMs, 40);
  });
  test('direct signaling drops public, relay and reflexive ICE candidates', () {
    final sdp = [
      'v=0',
      'a=fingerprint:sha-256 FF',
      'a=candidate:1 1 udp 1 192.168.49.1 1234 typ host',
      'a=candidate:2 1 udp 1 10.0.0.1 1234 typ host',
      'a=candidate:3 1 udp 1 172.16.1.1 1234 typ host',
      'a=candidate:4 1 udp 1 8.8.8.8 1234 typ host',
      'a=candidate:5 1 udp 1 192.168.1.1 1234 typ relay',
      'a=candidate:6 1 udp 1 172.32.1.1 1234 typ host',
      'a=candidate:7 1 udp 1 192.168.500.1 1234 typ host',
      '',
    ].join('\r\n');
    final filtered = HybridAudio.privateCandidatesOnly(sdp);
    expect(filtered, contains('fingerprint'));
    expect(filtered, contains('192.168.49.1'));
    expect(filtered, contains('10.0.0.1'));
    expect(filtered, contains('172.16.1.1'));
    expect(filtered, isNot(contains('8.8.8.8')));
    expect(filtered, isNot(contains('typ relay')));
    expect(filtered, isNot(contains('172.32.1.1')));
    expect(filtered, isNot(contains('192.168.500.1')));
  });
}
