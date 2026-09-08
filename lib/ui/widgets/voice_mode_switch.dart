import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/session/room_session.dart';
import '../theme/app_theme.dart';

/// 房内发言方式切换器。
///
/// 两个选项始终同时可见；底层高亮块平滑滑动，避免系统分段按钮在深色房间背景上
/// 显得突兀。标题保持稳定，辅助说明让用户不用试按也能理解两种模式。
class VoiceModeSwitch extends StatelessWidget {
  const VoiceModeSwitch({
    super.key,
    required this.value,
    required this.isNight,
    required this.onChanged,
    this.dense = false,
  });

  final VoiceMode value;
  final bool isNight;
  final ValueChanged<VoiceMode> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final automatic = value == VoiceMode.automatic;
    final primary =
        isNight ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final secondary =
        isNight ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    final surface =
        isNight
            ? AppTheme.darkCardBg.withValues(alpha: 0.86)
            : AppTheme.lightCardBg.withValues(alpha: 0.90);

    return Semantics(
      container: true,
      label: '发言模式',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final compact =
                dense || constraints.maxWidth < 330 || textScale > 1.25;
            final height = dense ? 46.0 : (compact ? 58.0 : 68.0);
            final inset = dense ? 3.0 : 4.0;
            final optionWidth = (constraints.maxWidth - inset * 2) / 2;

            return Container(
              height: height,
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(dense ? 19 : 23),
                border: Border.all(
                  color:
                      isNight
                          ? Colors.white.withValues(alpha: 0.10)
                          : AppTheme.dawnBurgundy.withValues(alpha: 0.12),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: isNight ? 0.18 : 0.07,
                    ),
                    blurRadius: 18,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    left: inset + (automatic ? optionWidth : 0),
                    top: inset,
                    bottom: inset,
                    width: optionWidth,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: _selectedGradient(automatic),
                        ),
                        borderRadius: BorderRadius.circular(dense ? 16 : 19),
                        boxShadow: [
                          BoxShadow(
                            color: _accent(automatic).withValues(alpha: 0.28),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _ModeOption(
                          title: '按住对讲',
                          hint: '按住发送',
                          icon: Icons.touch_app_rounded,
                          selected: !automatic,
                          compact: compact,
                          primary: primary,
                          secondary: secondary,
                          selectedForeground: Colors.white,
                          onTap: () => _select(VoiceMode.pushToTalk),
                        ),
                      ),
                      Expanded(
                        child: _ModeOption(
                          title: '自动通话',
                          hint: '声音触发',
                          icon: Icons.graphic_eq_rounded,
                          selected: automatic,
                          compact: compact,
                          primary: primary,
                          secondary: secondary,
                          selectedForeground:
                              isNight
                                  ? Colors.white
                                  : AppTheme.lightTextPrimary,
                          onTap: () => _select(VoiceMode.automatic),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _select(VoiceMode mode) {
    if (mode == value) {
      return;
    }
    HapticFeedback.selectionClick();
    onChanged(mode);
  }

  List<Color> _selectedGradient(bool automatic) {
    if (isNight) {
      return automatic
          ? const [Color(0xFF286A71), Color(0xFF4B9A8C)]
          : const [AppTheme.nightDeepOcean, Color(0xFF5275A9)];
    }
    return automatic
        ? const [AppTheme.dawnCoral, Color(0xFFE4B074)]
        : const [Color(0xFF7E3947), Color(0xFFA75559)];
  }

  Color _accent(bool automatic) {
    if (isNight) {
      return automatic ? const Color(0xFF4B9A8C) : AppTheme.nightSkyBlue;
    }
    return automatic ? const Color(0xFFD99A68) : AppTheme.dawnBurgundy;
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.title,
    required this.hint,
    required this.icon,
    required this.selected,
    required this.compact,
    required this.primary,
    required this.secondary,
    required this.selectedForeground,
    required this.onTap,
  });

  final String title;
  final String hint;
  final IconData icon;
  final bool selected;
  final bool compact;
  final Color primary;
  final Color secondary;
  final Color selectedForeground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? selectedForeground : primary;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title，$hint',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(19),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  scale: selected ? 1 : 0.90,
                  child: Icon(icon, size: compact ? 19 : 21, color: foreground),
                ),
                SizedBox(width: compact ? 6 : 9),
                Flexible(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: TextStyle(
                          color: foreground,
                          fontSize: compact ? 13 : 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 2),
                        Text(
                          hint,
                          maxLines: 1,
                          style: TextStyle(
                            color:
                                selected
                                    ? selectedForeground.withValues(alpha: 0.78)
                                    : secondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
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
