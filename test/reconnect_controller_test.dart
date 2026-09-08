import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dawn_mesh/core/session/reconnect_controller.dart';

void main() {
  test('retries with a capped delay until the recovery window expires', () {
    fakeAsync((async) {
      final epoch = DateTime(2026);
      var attempts = 0;
      var failed = false;
      final controller = ReconnectController(
        delays: const [Duration(milliseconds: 100)],
        recoveryWindow: const Duration(milliseconds: 350),
        now: () => epoch.add(async.elapsed),
        onAttemptReconnect: () async {
          attempts++;
          return false;
        },
        onMaxRetriesReached: () => failed = true,
      );

      controller.start();
      async.elapse(const Duration(milliseconds: 349));
      async.flushMicrotasks();
      expect(attempts, 3);
      expect(failed, isFalse);
      expect(controller.isReconnecting, isTrue);

      async.elapse(const Duration(milliseconds: 1));
      expect(failed, isTrue);
      expect(controller.isReconnecting, isFalse);
    });
  });

  test('a repeated start does not reset the active recovery window', () {
    fakeAsync((async) {
      final epoch = DateTime(2026);
      var failed = false;
      final controller = ReconnectController(
        delays: const [Duration(milliseconds: 100)],
        recoveryWindow: const Duration(milliseconds: 250),
        now: () => epoch.add(async.elapsed),
        onAttemptReconnect: () async => false,
        onMaxRetriesReached: () => failed = true,
      );

      controller.start();
      async.elapse(const Duration(milliseconds: 150));
      async.flushMicrotasks();
      controller.start();
      async.elapse(const Duration(milliseconds: 100));
      async.flushMicrotasks();

      expect(failed, isTrue);
      expect(controller.elapsed, Duration.zero);
    });
  });

  test('the production recovery window is ten minutes', () {
    final controller = ReconnectController(
      onAttemptReconnect: () async => false,
      onMaxRetriesReached: () {},
    );
    expect(controller.recoveryWindow, const Duration(minutes: 10));
    controller.cancel();
  });
}
