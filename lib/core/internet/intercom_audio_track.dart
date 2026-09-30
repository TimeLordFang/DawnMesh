// The app owns capture across LiveKit publication lifetimes. This constructor
// is verified against the pinned livekit_client 2.12.0 API.
// ignore_for_file: invalid_use_of_internal_member
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

import '../diagnostics/app_log.dart';

class IntercomAudioTrack extends LocalAudioTrack {
  IntercomAudioTrack(
    rtc.MediaStream stream,
    rtc.MediaStreamTrack track,
    AudioCaptureOptions options, {
    required this.mayTransmit,
    Future<rtc.MediaStream> Function(AudioCaptureOptions)? createStream,
  }) : _createStream = createStream ?? LocalTrack.createStream,
       super(TrackSource.microphone, stream, track, options) {
    track.enabled = false;
  }

  final bool Function() mayTransmit;
  final Future<rtc.MediaStream> Function(AudioCaptureOptions) _createStream;
  bool get _allowed => !_released && mayTransmit();

  /// Close immediately, even while a queued capture restart/publish is pending.
  void blockTransmission() {
    if (!_released) mediaStreamTrack.enabled = false;
  }

  @override
  Future<void> enable() async {
    if (!_allowed) {
      blockTransmission();
      return;
    }
    await super.enable();
    if (!_allowed) blockTransmission();
  }

  @override
  Future<bool> mute({bool stopOnMute = true}) {
    // SDK mute() otherwise returns early when its cached muted flag is true.
    blockTransmission();
    return super.mute(stopOnMute: stopOnMute);
  }

  @override
  Future<bool> unmute({bool stopOnMute = true}) async {
    if (!_allowed) {
      AppLog.warn('DawnInternet', '已拦截不符合本机对讲状态的麦克风开启请求');
      await mute(stopOnMute: false);
      return false;
    }
    final changed = await super.unmute(stopOnMute: stopOnMute);
    // A quick release/re-press can close native capture before queued mute()
    // updates the SDK flag. An allowed unmute must reconcile both states.
    if (_allowed && !muted) {
      await enable();
    } else {
      await mute(stopOnMute: false);
    }
    if (!_allowed) blockTransmission();
    return changed;
  }

  @override
  void updateMediaStreamAndTrack(
    rtc.MediaStream stream,
    rtc.MediaStreamTrack track,
  ) {
    track.enabled = _allowed && !muted;
    super.updateMediaStreamAndTrack(stream, track);
  }

  // The SDK restart attaches a newly enabled native track before updating its
  // cached stream. Gate it BEFORE attaching, including release during getUserMedia.
  @override
  Future<void> restartTrack([LocalTrackOptions? options]) async {
    if (_released) throw StateError('Microphone already released');
    if (options != null && options is! AudioCaptureOptions) {
      throw ArgumentError('AudioCaptureOptions required');
    }
    currentOptions = options as AudioCaptureOptions? ?? currentOptions;
    await stop();
    final stream = await _createStream(currentOptions);
    final track = stream.getAudioTracks().first;
    track.enabled = false;
    if (_released) {
      await track.stop();
      await stream.dispose();
      return;
    }
    updateMediaStreamAndTrack(stream, track);
    try {
      await sender?.replaceTrack(track);
    } catch (error) {
      AppLog.warn('DawnInternet', '采集已更新，等待公网发送器恢复：$error');
    } finally {
      // Capture remains usable by direct senders even if the SFU sender vanished.
      await start();
      if (!_allowed || muted) blockTransmission();
    }
  }

  static Future<IntercomAudioTrack> createOwned(
    AudioCaptureOptions options, {
    required bool Function() mayTransmit,
  }) async {
    final stream = await LocalTrack.createStream(options);
    final track = IntercomAudioTrack(
      stream,
      stream.getAudioTracks().first,
      options,
      mayTransmit: mayTransmit,
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
  Future<bool> start() async {
    if (_released) throw StateError('Microphone already released');
    final started = await super.start();
    if (!_allowed || muted) blockTransmission();
    return started;
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
