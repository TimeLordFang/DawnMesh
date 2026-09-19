import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../theme/app_theme.dart';

class RecentMessagePreviewItem {
  const RecentMessagePreviewItem({
    required this.sender,
    required this.text,
    this.isMine = false,
  });

  final String sender;
  final String text;
  final bool isMine;
}

/// 房间主界面的最近消息字幕带。
///
/// 它只承担“扫一眼”的职责：保留最近两到三条、每条单行截断；完整历史、
/// 输入和消息管理仍由聊天面板负责。
class RecentMessagesStrip extends StatelessWidget {
  const RecentMessagesStrip({
    super.key,
    required this.messages,
    required this.isNight,
    required this.onTap,
    this.unreadCount = 0,
    this.maxVisible = 3,
  });

  final List<RecentMessagePreviewItem> messages;
  final bool isNight;
  final VoidCallback onTap;
  final int unreadCount;
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) return const SizedBox.shrink();

    final s = AppStrings.of(context);
    final accent = isNight ? AppTheme.nightSkyBlue : AppTheme.dawnBurgundy;
    final primary = isNight
        ? AppTheme.darkTextPrimary
        : AppTheme.lightTextPrimary;
    final secondary = isNight
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;
    final surface = isNight
        ? AppTheme.darkCardBg.withValues(alpha: .72)
        : AppTheme.lightCardBg.withValues(alpha: .76);
    final visible = messages.length <= maxVisible
        ? messages
        : messages.sublist(messages.length - maxVisible);

    return Semantics(
      button: true,
      label: s.recentMessages,
      hint: unreadCount > 0
          ? s.chatUnreadBadge(unreadCount)
          : s.viewAllMessages,
      child: Material(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: const ValueKey('recent-messages-strip'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 9, 10, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.forum_outlined, size: 17, color: accent),
                    const SizedBox(width: 7),
                    Text(
                      s.recentMessages,
                      style: TextStyle(
                        color: primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    if (unreadCount > 0)
                      Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.only(right: 7),
                        decoration: BoxDecoration(
                          color: isNight
                              ? AppTheme.darkLeaveRosePink
                              : AppTheme.dawnCoral,
                          shape: BoxShape.circle,
                        ),
                      ),
                    Text(
                      s.viewAllMessages,
                      style: TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 18, color: accent),
                  ],
                ),
                const SizedBox(height: 5),
                for (final message in visible)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 2,
                          height: 15,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: message.isMine
                                ? accent.withValues(alpha: .9)
                                : secondary.withValues(alpha: .38),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 76),
                          child: Text(
                            message.isMine ? s.chatSelfBadge : message.sender,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: secondary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            message.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: primary.withValues(alpha: .92),
                              fontSize: 12.5,
                              height: 1.15,
                            ),
                          ),
                        ),
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
