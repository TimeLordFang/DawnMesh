import 'dart:async';

import 'app_log.dart';

class _MetricSamples {
  static const int capacity = 512;
  final List<int> values = [];
  int count = 0;

  void add(int value) {
    final safe = value < 0 ? 0 : value;
    count++;
    if (values.length == capacity) values.removeAt(0);
    values.add(safe);
  }

  String summary() {
    if (values.isEmpty) return 'n=0';
    final sorted = [...values]..sort();
    int percentile(double p) => sorted[((sorted.length - 1) * p).floor()];
    final total = sorted.fold<int>(0, (sum, value) => sum + value);
    return 'n=${sorted.length}/$count,avg=${total ~/ sorted.length}us,'
        'p50=${percentile(.50)}us,p95=${percentile(.95)}us,'
        'p99=${percentile(.99)}us,max=${sorted.last}us';
  }
}

/// Dart/Flutter 部分的低开销滚动统计。仅在应用内调试日志开启时采样。
class PipelineProbe {
  PipelineProbe._();

  static final Stopwatch _clock = Stopwatch()..start();
  static final Map<String, _MetricSamples> _metrics = {};
  static Timer? _timer;

  static int nowMicros() => _clock.elapsedMicroseconds;

  static void record(String name, int durationMicros) {
    if (!AppLog.isEnabled) return;
    (_metrics[name] ??= _MetricSamples()).add(durationMicros);
    _timer ??= Timer.periodic(const Duration(seconds: 10), (_) => report());
  }

  static void report() {
    if (!AppLog.isEnabled || _metrics.isEmpty) return;
    final details = _metrics.entries
        .map((entry) => '${entry.key}[${entry.value.summary()}]')
        .join(',');
    AppLog.debug('DawnPipeline', details);
  }
}
