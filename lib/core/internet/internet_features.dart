/// Versioned data contract, not downloaded executable code. Unknown schemas
/// fail closed and old servers simply expose no optional native features.
class InternetFeatures {
  const InternetFeatures({
    this.hybridAudio = false,
    this.maxPeers = 4,
    this.maxRttMs = 120,
    this.stableSamples = 3,
    this.notice = '',
  });
  final bool hybridAudio;
  final int maxPeers;
  final int maxRttMs;
  final int stableSamples;
  final String notice;
  factory InternetFeatures.fromJson(Object? value) {
    if (value is! Map || value['schemaVersion'] != 1) {
      return const InternetFeatures();
    }
    int bounded(String key, int fallback, int min, int max) {
      final number = value[key];
      return number is int && number >= min && number <= max
          ? number
          : fallback;
    }

    final notice = value['notice'];
    return InternetFeatures(
      hybridAudio: value['hybridAudio'] == true,
      maxPeers: bounded('hybridMaxPeers', 4, 1, 4),
      maxRttMs: bounded('hybridMaxRttMs', 120, 40, 300),
      stableSamples: bounded('hybridStableSamples', 3, 3, 10),
      notice: notice is String && notice.length <= 600 ? notice : '',
    );
  }
}

/// Hysteresis prevents rapid route flapping. A bad/missing sample immediately
/// returns to the already subscribed SFU stream; promotion needs stable probes.
class HybridRoutePolicy {
  int goodSamples = 0;
  bool direct = false;
  bool update({
    required bool connected,
    required double? rttMs,
    required double? cloudRttMs,
    required double loss,
    required double jitterMs,
    required InternetFeatures features,
  }) {
    final good =
        connected &&
        rttMs != null &&
        rttMs.isFinite &&
        rttMs >= 0 &&
        rttMs <= features.maxRttMs &&
        loss.isFinite &&
        loss <= .03 &&
        loss >= 0 &&
        jitterMs.isFinite &&
        jitterMs <= 40 &&
        jitterMs >= 0 &&
        (cloudRttMs == null || rttMs <= cloudRttMs * .85);
    goodSamples = good ? goodSamples + 1 : 0;
    direct = good && (direct || goodSamples >= features.stableSamples);
    return direct;
  }
}
