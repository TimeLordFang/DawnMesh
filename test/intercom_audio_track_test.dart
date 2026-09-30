import 'package:dawn_mesh/core/internet/intercom_audio_track.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

class _Stream extends Fake implements rtc.MediaStream {
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
  test(
    'SDK publication disposal leaves capture alive; owner releases it once',
    () async {
      final stream = _Stream();
      final media = _Track();
      final track = IntercomAudioTrack(
        stream,
        media,
        const AudioCaptureOptions(),
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
