import 'dart:async';

/// 在给定恢复窗口内持续指数退避重连。
class ReconnectController {
  static const List<Duration> defaultDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  final List<Duration> delays;
  final Future<bool> Function() onAttemptReconnect;
  final void Function() onMaxRetriesReached;
  final Duration recoveryWindow;
  final DateTime Function() now;

  int _retryCount = 0;
  Timer? _timer;
  bool _isReconnecting = false;
  DateTime? _startedAt;

  ReconnectController({
    required this.onAttemptReconnect,
    required this.onMaxRetriesReached,
    this.delays = defaultDelays,
    this.recoveryWindow = const Duration(minutes: 10),
    DateTime Function()? now,
  }) : assert(delays.isNotEmpty),
       assert(recoveryWindow > Duration.zero),
       now = now ?? DateTime.now;

  bool get isReconnecting => _isReconnecting;
  int get retryCount => _retryCount;
  Duration get elapsed =>
      _startedAt == null ? Duration.zero : now().difference(_startedAt!);
  Duration get remaining {
    final value = recoveryWindow - elapsed;
    return value.isNegative ? Duration.zero : value;
  }

  void start() {
    if (_isReconnecting) return;
    cancel();
    _retryCount = 0;
    _isReconnecting = true;
    _startedAt = now();
    _scheduleNext();
  }

  void _scheduleNext() {
    if (!_isReconnecting) return;
    if (elapsed >= recoveryWindow) {
      _finishFailed();
      return;
    }

    final delay = delays[_retryCount.clamp(0, delays.length - 1)];
    if (elapsed + delay > recoveryWindow) {
      _timer = Timer(remaining, _finishFailed);
      return;
    }
    _timer = Timer(delay, () async {
      if (!_isReconnecting) return;
      _retryCount++;
      final success = await onAttemptReconnect();
      if (!_isReconnecting) return;
      if (success) {
        cancel();
      } else {
        _scheduleNext();
      }
    });
  }

  void _finishFailed() {
    if (!_isReconnecting) return;
    _timer?.cancel();
    _timer = null;
    _isReconnecting = false;
    _retryCount = 0;
    _startedAt = null;
    onMaxRetriesReached();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _isReconnecting = false;
    _retryCount = 0;
    _startedAt = null;
  }
}
