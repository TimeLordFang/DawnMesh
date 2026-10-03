import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dawn_mesh/core/fusion/fusion_audio_settings.dart';
import 'package:dawn_mesh/core/internet/internet_audio_profile.dart';
import 'package:dawn_mesh/ui/widgets/fusion_audio_profile_control.dart';
import 'package:dawn_mesh/ui/widgets/room_settings_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('quality choices fit the narrow room settings sheet and apply', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final applied = <int>[];
    final settings = FusionAudioSettings(
      applyBitrate: (value) async => applied.add(value),
    );
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 640),
              textScaler: TextScaler.linear(1.4),
            ),
            child: RoomSettingsButton(
              items: (_) => [FusionAudioProfileControl(settings: settings)],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('room-settings-button')));
    await tester.pumpAndSettle();
    for (final profile in InternetAudioProfile.values) {
      final chip = find.byKey(ValueKey('fusion-audio-${profile.name}'));
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(chip).selected, true);
      expect(applied.last, profile.bitrateFor(metered: true));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('same public-room bitrates, automatic network defaults and persistent manual choice', () async {
    final changes = StreamController<List<ConnectivityResult>>();
    final applied = <int>[];
    final settings = FusionAudioSettings(
      applyBitrate: (value) async => applied.add(value),
      readNetwork: () async => [ConnectivityResult.wifi],
      networkChanges: changes.stream,
    );
    addTearDown(() async {
      settings.dispose();
      await changes.close();
    });
    await settings.start();
    expect(settings.profile, InternetAudioProfile.clarity);
    expect(settings.bitrate, 32000);
    changes.add([ConnectivityResult.mobile]);
    await Future<void>.delayed(Duration.zero);
    expect(settings.profile, InternetAudioProfile.dataSaver);
    expect(settings.bitrate, 12000);
    await settings.select(InternetAudioProfile.balanced);
    expect(applied.last, 16000);
    changes.add([ConnectivityResult.wifi]);
    await Future<void>.delayed(Duration.zero);
    expect(settings.profile, InternetAudioProfile.balanced);
    expect(applied.last, 24000);
  });
  test(
    'a delayed initial network read cannot overwrite newer network events',
    () async {
      final read = Completer<List<ConnectivityResult>>();
      final changes = StreamController<List<ConnectivityResult>>();
      final settings = FusionAudioSettings(
        applyBitrate: (_) async {},
        readNetwork: () => read.future,
        networkChanges: changes.stream,
      );
      addTearDown(() async {
        settings.dispose();
        await changes.close();
      });
      final starting = settings.start();
      changes.add([ConnectivityResult.mobile]);
      await Future<void>.delayed(Duration.zero);
      read.complete([ConnectivityResult.wifi]);
      await starting;
      expect(settings.metered, true);
      expect(settings.bitrate, 12000);
    },
  );
}
