import 'dart:async';

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

  test('exceptions retry and a hung attempt cannot outlive the deadline', () {
    fakeAsync((async) {
      var attempts = 0;
      var expired = false;
      final controller = ReconnectController(
        delays: const [Duration(seconds: 1)],
        recoveryWindow: const Duration(seconds: 5),
        now: () => DateTime(2026).add(async.elapsed),
        onAttemptReconnect: () async {
          if (++attempts == 1) throw StateError('radio unavailable');
          return Completer<bool>().future;
        },
        onMaxRetriesReached: () => expired = true,
      );
      controller.start();
      async.elapse(const Duration(seconds: 5));
      expect(attempts, 2);
      expect(expired, isTrue);
      expect(controller.isReconnecting, isFalse);
    });
  });

  test('an old successful attempt cannot cancel a new recovery cycle', () {
    fakeAsync((async) {
      final old = Completer<bool>();
      var attempts = 0;
      final controller = ReconnectController(
        delays: const [Duration(seconds: 1)],
        now: () => DateTime(2026).add(async.elapsed),
        onAttemptReconnect: () =>
            ++attempts == 1 ? old.future : Future.value(false),
        onMaxRetriesReached: () {},
      );
      controller.start();
      async.elapse(const Duration(seconds: 1));
      controller.cancel();
      controller.start();
      old.complete(true);
      async.flushMicrotasks();
      expect(controller.isReconnecting, isTrue);
      async.elapse(const Duration(seconds: 1));
      expect(attempts, 2);
      controller.cancel();
    });
  });

  test('the production recovery window is thirty minutes', () {
    final controller = ReconnectController(
      onAttemptReconnect: () async => false,
      onMaxRetriesReached: () {},
    );
    expect(controller.recoveryWindow, const Duration(minutes: 30));
    controller.cancel();
  });
}
