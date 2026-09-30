// The app owns capture across LiveKit publication lifetimes. This constructor
// is verified against the pinned livekit_client 2.12.0 API.
// ignore_for_file: invalid_use_of_internal_member
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

class IntercomAudioTrack extends LocalAudioTrack {
  IntercomAudioTrack(
    rtc.MediaStream stream,
    rtc.MediaStreamTrack track,
    AudioCaptureOptions options,
  ) : super(TrackSource.microphone, stream, track, options);

  static Future<IntercomAudioTrack> createOwned(
    AudioCaptureOptions options,
  ) async {
    final stream = await LocalTrack.createStream(options);
    final track = IntercomAudioTrack(
      stream,
      stream.getAudioTracks().first,
      options,
    );
    try {
      await track.start();
      // A new capture must never transmit before the latest PTT/mute policy applies.
      await track.mute(stopOnMute: false);
      return track;
    } catch (_) {
      await track.release();
      rethrow;
    }
  }

  bool _released = false;
  @override
  Future<bool> start() {
    if (_released) throw StateError('Microphone already released');
    return super.start();
  }

  // LiveKit disposes its publications after SFU disconnection. Direct senders
  // still use this exact capture; only the session owner may release it.
  // The owner invokes the superclass exactly once via release().
  @override
  // ignore: must_call_super
  Future<bool> dispose() async => false;

  Future<bool> release() {
    _released = true;
    return super.dispose();
  }
}
