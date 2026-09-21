import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../../l10n/app_strings.dart';

/// Bottom audio controls: mute, output, microphone source, and leave.
class AudioControlsBar extends StatelessWidget {
  final bool isNight;
  final bool isMuted;
  final bool isSpeakerOn;
  final bool useBuiltinMic;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onToggleMicSource;
  final VoidCallback onLeave;
  final bool compact;

  const AudioControlsBar({
    super.key,
    required this.isNight,
    required this.isMuted,
    required this.isSpeakerOn,
    required this.useBuiltinMic,
    required this.onToggleMute,
    required this.onToggleSpeaker,
    required this.onToggleMicSource,
    required this.onLeave,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final leaveColor = isNight
        ? AppTheme.darkLeaveRosePink
        : AppTheme.lightLeaveAccent;
    final cardBg = isNight ? AppTheme.darkCardBg : AppTheme.lightCardBg;
    final textPrimary = isNight
        ? AppTheme.darkTextPrimary
        : AppTheme.lightTextPrimary;

    return RoomControlsBar(
      compact: compact,
      children: [
        RoomControlButton(
          icon: isMuted ? Icons.mic_off : Icons.mic,
          label: isMuted ? s.muted : s.microphone,
          isNight: isNight,
          onTap: onToggleMute,
          bgColor: cardBg,
          textColor: textPrimary,
          compact: compact,
        ),
        RoomControlButton(
          icon: isSpeakerOn ? Icons.volume_up : Icons.phone_in_talk,
          label: isSpeakerOn ? s.speaker : s.earpiece,
          isNight: isNight,
          onTap: onToggleSpeaker,
          bgColor: cardBg,
          textColor: textPrimary,
          compact: compact,
        ),
        RoomControlButton(
          icon: useBuiltinMic ? Icons.phone_android : Icons.headset_mic,
          label: useBuiltinMic ? s.phoneMic : s.headsetMic,
          isNight: isNight,
          onTap: onToggleMicSource,
          bgColor: cardBg,
          textColor: textPrimary,
          compact: compact,
        ),
        RoomControlButton(
          icon: Icons.call_end,
          label: s.hangUp,
          isNight: isNight,
          onTap: onLeave,
          bgColor: leaveColor.withValues(alpha: 0.15),
          borderColor: leaveColor.withValues(alpha: 0.62),
          textColor: leaveColor,
          compact: compact,
        ),
      ],
    );
  }
}

/// Identical four-slot control geometry for nearby and internet rooms.
class RoomControlsBar extends StatelessWidget {
  const RoomControlsBar({
    super.key,
    required this.children,
    this.compact = false,
  });

  final List<Widget> children;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    assert(children.length == 4);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 13, vertical: compact ? 4 : 18),
      child: Row(
        children: [for (final child in children) Expanded(child: child)],
      ),
    );
  }
}

class RoomControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isNight;
  final VoidCallback? onTap;
  final Color bgColor;
  final Color? borderColor;
  final Color textColor;
  final bool compact;

  const RoomControlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.isNight,
    required this.onTap,
    required this.bgColor,
    this.borderColor,
    required this.textColor,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    // 四个按钮均分底部宽度：放大字号后，360dp 的窄屏上原来的自适应宽度会挤爆。
    // 均分之后再套一层 FittedBox，更窄的屏上是整体缩小而不是溢出。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 7 : 10,
            vertical: compact ? 7 : 14,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color:
                  borderColor ??
                  (isNight ? const Color(0xFF283A52) : const Color(0xFFDCCEC8)),
              width: 1.4,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: compact ? 20 : 24, color: textColor),
                SizedBox(width: compact ? 5 : 8),
                Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: compact ? 12 : 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
