import 'dart:async';

import 'package:dawn_mesh/core/internet/exclusive_audio_switch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'no overlapping playback during promotion, fallback, or rapid reversal',
    () async {
      bool cloud = true, direct = false;
      final order = <String>[];
      Future<void> cloudPlayback(bool enabled) async {
        await Future<void>.delayed(Duration.zero);
        cloud = enabled;
        order.add('cloud:$enabled');
        expect(cloud && direct, isFalse);
      }

      Future<void> directPlayback(bool enabled) async {
        await Future<void>.delayed(Duration.zero);
        direct = enabled;
        order.add('direct:$enabled');
        expect(cloud && direct, isFalse);
      }

      for (final select in [true, false, true, false]) {
        await switchExclusiveAudio(
          direct: select,
          cloudPlayback: cloudPlayback,
          directPlayback: directPlayback,
        );
        expect(direct, select);
        expect(cloud, !select);
      }
      expect(order.take(4), [
        'cloud:false',
        'direct:true',
        'direct:false',
        'cloud:true',
      ]);
    },
  );
  test('failed old-track mute never opens second audio output', () async {
    var enabledCloud = false;
    await expectLater(
      switchExclusiveAudio(
        direct: false,
        directPlayback: (_) async {
          throw StateError('native mute failed');
        },
        cloudPlayback: (enabled) async {
          enabledCloud = enabled;
        },
      ),
      throwsStateError,
    );
    expect(enabledCloud, isFalse);
  });
  test('waits for native mute completion before enabling direct', () async {
    final mute = Completer<void>();
    var direct = false;
    final switcher = switchExclusiveAudio(
      direct: true,
      cloudPlayback: (_) => mute.future,
      directPlayback: (enabled) async {
        direct = enabled;
      },
    );
    await Future<void>.delayed(Duration.zero);
    expect(direct, isFalse);
    mute.complete();
    await switcher;
    expect(direct, isTrue);
  });
}
