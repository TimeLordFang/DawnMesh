import 'dart:math';

import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

class HybridProbe {
  const HybridProbe({
    required this.rttMs,
    required this.loss,
    required this.jitterMs,
    required this.audioFlow,
  });
  final double? rttMs;
  final double loss, jitterMs;
  final bool audioFlow;
}

class HybridProbeSampler {
  final Map<String, (int, int)> _previous = {};
  HybridProbe sample(List<rtc.StatsReport> reports) {
    final selected = reports
        .where((s) => s.type == 'transport')
        .map((s) => s.values['selectedCandidatePairId'])
        .whereType<String>()
        .toSet();
    double? rtt;
    var receivedDelta = 0, lostDelta = 0;
    double jitter = 0;
    final currentIds = <String>{};
    for (final s in reports) {
      final v = s.values;
      if (s.type == 'candidate-pair' &&
          v['state'] == 'succeeded' &&
          (selected.isNotEmpty
              ? selected.contains(s.id)
              : v['nominated'] == true)) {
        final seconds = v['currentRoundTripTime'];
        if (seconds is num && seconds.isFinite && seconds >= 0) {
          rtt = seconds.toDouble() * 1000;
        }
      }
      if (s.type != 'inbound-rtp' ||
          (v['kind'] != 'audio' && v['mediaType'] != 'audio')) {
        continue;
      }
      currentIds.add(s.id);
      final received = (v['packetsReceived'] as num?)?.toInt() ?? 0;
      final lost = (v['packetsLost'] as num?)?.toInt() ?? 0;
      final previous = _previous[s.id];
      receivedDelta += max(0, received - (previous?.$1 ?? 0));
      lostDelta += max(0, lost - (previous?.$2 ?? 0));
      _previous[s.id] = (received, lost);
      jitter = max(jitter, ((v['jitter'] as num?)?.toDouble() ?? 0) * 1000);
    }
    _previous.removeWhere((id, _) => !currentIds.contains(id));
    return HybridProbe(
      rttMs: rtt,
      loss: receivedDelta + lostDelta > 0
          ? lostDelta / (receivedDelta + lostDelta)
          : 0,
      jitterMs: jitter,
      audioFlow: receivedDelta > 0,
    );
  }
}
