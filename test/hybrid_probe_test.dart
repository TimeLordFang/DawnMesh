import 'package:dawn_mesh/core/internet/hybrid_probe.dart';
import 'package:dawn_mesh/core/internet/hybrid_offline_lease.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

void main() {
  test('uses the selected ICE pair instead of another nominated pair', () {
    final probe = HybridProbeSampler().sample([
      StatsReport('transport', 'transport', 0, {
        'selectedCandidatePairId': 'wifi',
      }),
      StatsReport('wifi', 'candidate-pair', 0, {
        'state': 'succeeded',
        'currentRoundTripTime': .015,
      }),
      StatsReport('other', 'candidate-pair', 0, {
        'state': 'succeeded',
        'nominated': true,
        'currentRoundTripTime': .9,
      }),
    ]);
    expect(probe.rttMs, 15);
    expect(probe.audioFlow, false);
  });
  test('per-stream packet deltas tolerate SSRC restarts and DTX silence', () {
    final sampler = HybridProbeSampler();
    HybridProbe sample(int received, int lost) => sampler.sample([
      StatsReport('a', 'inbound-rtp', 0, {
        'kind': 'audio',
        'packetsReceived': received,
        'packetsLost': lost,
        'jitter': .02,
      }),
    ]);
    sample(100, 0);
    final loss = sample(190, 10);
    expect(loss.loss, .1);
    expect(loss.jitterMs, 20);
    final reset = sample(2, 0);
    expect(reset.loss, 0);
    expect(sample(2, 0).audioFlow, false);
    expect(sample(3, 0).audioFlow, true);
  });
  test('offline continuity expires after thirty minutes and fresh authority renews it', () {
    final now = DateTime.utc(2026, 9, 30);
    final lease = HybridOfflineLease();
    lease.update(authorityOnline: false, now: now);
    lease.update(
      authorityOnline: false,
      now: now.add(const Duration(minutes: 20)),
    );
    expect(lease.allows(now.add(const Duration(minutes: 29))), true);
    expect(lease.allows(now.add(const Duration(minutes: 30))), false);
    lease.update(
      authorityOnline: true,
      now: now.add(const Duration(minutes: 31)),
    );
    expect(lease.allows(now.add(const Duration(minutes: 32))), true);
  });
}
