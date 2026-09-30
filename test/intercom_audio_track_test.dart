import 'dart:async';

import 'package:dawn_mesh/core/internet/intercom_audio_track.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

class _Stream extends Fake implements rtc.MediaStream {
  _Stream([this.audio]);
  final rtc.MediaStreamTrack? audio;
  @override
  List<rtc.MediaStreamTrack> getAudioTracks() => [audio!];
  int disposals = 0;
  @override
  Future<void> dispose() async {
    disposals++;
  }
}

class _Track extends Fake implements rtc.MediaStreamTrack {
  @override
  String get id => 'owned-mic';
  @override
  String get kind => 'audio';
  @override
  bool enabled = true;
  @override
  void Function()? onEnded;
  int stops = 0;
  @override
  Future<void> stop() async {
    stops++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('quick PTT release and re-press reopens capture even before cached mute updates', () async {
    var pressed = true;
    final media = _Track();
    final track = IntercomAudioTrack(
      _Stream(),
      media,
      const AudioCaptureOptions(),
      mayTransmit: () => pressed,
    );
    addTearDown(track.release);
    await track.start();
    await track.mute(stopOnMute: false);
    await track.unmute(stopOnMute: false);
    expect(media.enabled, true);
    pressed = false;
    track.blockTransmission();
    expect(media.enabled, false);
    expect(track.muted, false); // queued mute has not run yet
    pressed = true;
    await track.unmute(stopOnMute: false);
    expect(media.enabled, true);
    pressed = false;
    track.blockTransmission();
    await track.unmute(
      stopOnMute: false,
    ); // a stale SDK request must still fail
    expect(media.enabled, false);
    expect(track.muted, true);
  });
  test(
    'SDK unmute/enable cannot open an idle PTT microphone after reconnect',
    () async {
      var pressed = false;
      final media = _Track();
      final track = IntercomAudioTrack(
        _Stream(),
        media,
        const AudioCaptureOptions(),
        mayTransmit: () => pressed,
      );
      addTearDown(track.release);
      await track.start();
      await track.mute(stopOnMute: false);
      await track.unmute(stopOnMute: false); // SDK remote-unmute path
      await track.enable();
      expect(media.enabled, false);
      expect(track.muted, true);
      pressed = true;
      await track.unmute(stopOnMute: false);
      expect(media.enabled, true);
      pressed = false;
      track.blockTransmission();
      expect(media.enabled, false);
      await track.mute(stopOnMute: false);
      await track.dispose(); // SFU cleanup followed by republish
      await track.start();
      await track.unmute(stopOnMute: false);
      expect(media.enabled, false);
      expect(track.muted, true);
    },
  );
  test(
    'mute repairs an enabled native track even with a cached muted flag',
    () async {
      final media = _Track();
      final track = IntercomAudioTrack(
        _Stream(),
        media,
        const AudioCaptureOptions(),
        mayTransmit: () => false,
      );
      addTearDown(track.release);
      await track.start();
      await track.mute(stopOnMute: false);
      media.enabled = true; // Native/SDK state changed independently.
      await track.mute(stopOnMute: false);
      expect(media.enabled, false);
    },
  );
  test(
    'PTT released during capture replacement never attaches an enabled track',
    () async {
      var pressed = true;
      final replacement = Completer<rtc.MediaStream>();
      final media = _Track();
      final sender = _Sender();
      final track = IntercomAudioTrack(
        _Stream(),
        media,
        const AudioCaptureOptions(),
        mayTransmit: () => pressed,
        createStream: (_) => replacement.future,
      );
      addTearDown(track.release);
      await track.start();
      await track.mute(stopOnMute: false);
      await track.unmute(stopOnMute: false);
      track.transceiver = _Transceiver(sender);
      final restarting = track.restartTrack();
      pressed = false;
      track.blockTransmission();
      final fresh = _Track();
      replacement.complete(_Stream(fresh));
      await restarting;
      expect(sender.enabledWhenAttached, false);
      expect(fresh.enabled, false);
      await track.unmute(stopOnMute: false);
      expect(fresh.enabled, false);
    },
  );
  test(
    'SDK publication disposal leaves capture alive; owner releases it once',
    () async {
      final stream = _Stream();
      final media = _Track();
      final track = IntercomAudioTrack(
        stream,
        media,
        const AudioCaptureOptions(),
        mayTransmit: () => true,
      );
      await track.start();
      await track.dispose();
      expect(track.isActive, true);
      expect(media.stops, 0);
      expect(stream.disposals, 0);
      await track.mute(stopOnMute: false);
      expect(media.enabled, false);
      await track.unmute(stopOnMute: false);
      expect(media.enabled, true);
      await track.release();
      expect(track.isActive, false);
      expect(media.stops, greaterThan(0));
      expect(stream.disposals, 1);
      await track.release();
      expect(stream.disposals, 1);
    },
  );
}

class _Sender extends Fake implements rtc.RTCRtpSender {
  bool? enabledWhenAttached;
  @override
  Future<void> replaceTrack(rtc.MediaStreamTrack? track) async {
    enabledWhenAttached = track?.enabled;
  }
}

class _Transceiver extends Fake implements rtc.RTCRtpTransceiver {
  _Transceiver(this.sender);
  @override
  final rtc.RTCRtpSender sender;
}
