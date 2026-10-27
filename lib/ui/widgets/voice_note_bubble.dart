import 'package:flutter/material.dart';

import '../../core/session/chat_message.dart';
import '../../core/session/room_session.dart';
import '../../l10n/app_strings.dart';

class VoiceNoteBubble extends StatelessWidget {
  const VoiceNoteBubble({
    super.key,
    required this.message,
    required this.session,
  });
  final ChatMessage message;
  final RoomSession session;

  @override
  Widget build(BuildContext context) => StreamBuilder<void>(
    stream: session.controlsStream,
    builder: (context, _) {
      final s = AppStrings.of(context);
      final playing = session.playingVoiceMessageId == message.messageId;
      final seconds = ((message.voiceNote?.duration.inMilliseconds ?? 0) / 1000)
          .toStringAsFixed(1);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: playing ? s.stopVoiceNote : s.playVoiceNote,
            onPressed: message.voicePending
                ? null
                : () async {
                    try {
                      if (playing) {
                        await session.stopVoiceNote();
                      } else {
                        await session.playVoiceNote(message.messageId);
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(s.voiceNotePlaybackFailed)),
                        );
                      }
                    }
                  },
            icon: Icon(
              message.voicePending
                  ? Icons.hourglass_top_rounded
                  : playing
                  ? Icons.stop_circle_outlined
                  : Icons.play_circle_outline_rounded,
            ),
          ),
          Flexible(
            child: Text(
              message.voicePending
                  ? s.voiceNotePending
                  : s.voiceNoteDuration(seconds),
            ),
          ),
          if (message.voicePending && message.isLocal)
            IconButton(
              tooltip: s.cancelVoiceNote,
              onPressed: () => session.recallMessage(message.messageId),
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      );
    },
  );
}
