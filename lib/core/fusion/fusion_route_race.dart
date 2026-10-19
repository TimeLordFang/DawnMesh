import 'dart:async';

/// Prefer local candidates while allowing an independent cloud route to rescue
/// a stalled dial or an open socket which never completes room admission.
abstract final class FusionRouteRace {
  static Future<bool> connect({
    required List<Future<bool> Function()> local,
    Future<bool> Function()? cloud,
    bool Function()? finished,
    Duration cloudDelay = const Duration(milliseconds: 600),
    Duration localFallbackDelay = const Duration(milliseconds: 1500),
  }) async {
    final result = Completer<bool>();
    var remaining = cloud == null ? 1 : 2;
    bool done() => finished?.call() ?? false;
    Future<void> run(Future<bool> Function() action) async {
      var connected = false;
      try {
        connected = await action();
      } catch (_) {
        /* Try another route. */
      }
      if (connected && !result.isCompleted) result.complete(true);
      if (--remaining == 0 && !result.isCompleted) result.complete(false);
    }

    unawaited(
      run(() async {
        var connected = false;
        for (var index = 0; index < local.length; index++) {
          if (done()) return connected;
          try {
            if (await local[index]()) {
              connected = true;
              if (!result.isCompleted) result.complete(true);
              // A socket opening is not room admission. Keep the first route
              // while another local endpoint can rescue a silent handshake.
              if (finished == null) return true;
              if (index + 1 < local.length) {
                await Future<void>.delayed(localFallbackDelay);
              }
            }
          } catch (_) {
            /* Next. */
          }
        }
        return connected;
      }),
    );
    if (cloud != null) {
      unawaited(
        run(() async {
          await Future<void>.delayed(cloudDelay);
          if (done()) return false;
          return cloud();
        }),
      );
    }
    return result.future;
  }
}
