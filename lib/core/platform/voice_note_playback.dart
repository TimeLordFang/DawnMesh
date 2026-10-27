import 'package:flutter/services.dart';

import '../session/voice_note.dart';

/// Native playback uses a dedicated decoder, leaving live-call jitter buffers
/// and encoder state intact. The method completes on finish, stop, or failure.
class VoiceNotePlayback {
  static const _channel = MethodChannel('dev.dawnmesh.intercom/audio');
  Future<void> play(VoiceNote note) async {
    await _channel.invokeMethod<bool>('playVoiceNote', {'data': note.encode()});
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stopVoiceNote');
    } on MissingPluginException {
      /* The mock audio backend has no native player. */
    }
  }
}
