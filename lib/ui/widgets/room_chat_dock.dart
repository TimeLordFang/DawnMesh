import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../theme/app_theme.dart';

class RoomChatDockItem {
  const RoomChatDockItem({
    required this.sender,
    required this.text,
    this.isMine = false,
    this.hasImage = false,
  });

  final String sender;
  final String text;
  final bool isMine;
  final bool hasImage;
}

/// The room's always-visible chat surface: a quiet two-line transcript plus
/// the composer. Full history remains one tap away without competing with the
/// voice controls for a top-bar action.
class RoomChatDock extends StatefulWidget {
  const RoomChatDock({
    super.key,
    required this.messages,
    required this.isNight,
    required this.onOpenHistory,
    required this.onOpenComposer,
    required this.onPickImage,
    this.unreadCount = 0,
    this.enabled = true,
    this.visibleMessageCount = 3,
    this.messageMaxLines = 2,
    this.compact = false,
    this.expandedPreview = false,
    this.margin = const EdgeInsets.symmetric(horizontal: 18),
  });

  final List<RoomChatDockItem> messages;
  final bool isNight;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenComposer;
  final Future<void> Function() onPickImage;
  final int unreadCount;
  final bool enabled;
  final int visibleMessageCount;
  final int messageMaxLines;
  final bool compact;
  final bool expandedPreview;
  final EdgeInsetsGeometry margin;

  @override
  State<RoomChatDock> createState() => _RoomChatDockState();
}

class _RoomChatDockState extends State<RoomChatDock> {
  bool _busy = false;

  Future<void> _pickImage() async {
    if (_busy || !widget.enabled) return;
    setState(() => _busy = true);
    try {
      await widget.onPickImage();
    } catch (error) {
      if (mounted) _showError('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String error) {
    final message = error
        .replaceFirst('FormatException: ', '')
        .replaceFirst('Invalid argument(s): ', '');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final accent = widget.isNight
        ? AppTheme.nightSkyBlue
        : AppTheme.dawnBurgundy;
    final primary = widget.isNight
        ? AppTheme.darkTextPrimary
        : AppTheme.lightTextPrimary;
    final secondary = widget.isNight
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;
    final surface = widget.isNight
        ? AppTheme.darkCardBg.withValues(alpha: .82)
        : AppTheme.lightCardBg.withValues(alpha: .88);
    final visible = widget.messages.length <= widget.visibleMessageCount
        ? widget.messages
        : widget.messages.sublist(
            widget.messages.length - widget.visibleMessageCount,
          );

    return Padding(
      padding: widget.margin,
      child: Container(
        key: const ValueKey('room-chat-dock'),
        padding: EdgeInsets.fromLTRB(
          12,
          widget.compact ? 5 : 9,
          8,
          widget.compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: accent.withValues(alpha: .22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              key: const ValueKey('open-chat-history'),
              onTap: widget.onOpenHistory,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 0, 5),
                child: Row(
                  children: [
                    Icon(Icons.forum_outlined, size: 16, color: accent),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        s.recentMessages,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: primary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (widget.unreadCount > 0)
                      Container(
                        key: const ValueKey('chat-unread-dot'),
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: widget.isNight
                              ? AppTheme.darkLeaveRosePink
                              : AppTheme.dawnCoral,
                          shape: BoxShape.circle,
                        ),
                      ),
                    Text(
                      s.viewAllMessages,
                      style: TextStyle(
                        color: accent,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 17, color: accent),
                  ],
                ),
              ),
            ),
            ConstrainedBox(
              key: const ValueKey('room-chat-preview'),
              constraints: BoxConstraints(
                minHeight: widget.expandedPreview
                    ? 64
                    : (widget.compact ? 30 : 42),
                maxHeight: widget.expandedPreview
                    ? 132
                    : (widget.compact ? 58 : 96),
              ),
              child: visible.isEmpty
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        s.chatDockEmpty,
                        style: TextStyle(color: secondary, fontSize: 12),
                      ),
                    )
                  : ClipRect(
                      child: SingleChildScrollView(
                        reverse: true,
                        physics: const NeverScrollableScrollPhysics(),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            for (final message in visible)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 1,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 72,
                                      ),
                                      child: Text(
                                        message.isMine
                                            ? s.chatSelfBadge
                                            : message.sender,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: secondary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    Expanded(
                                      child: Text(
                                        message.hasImage
                                            ? '📷 ${s.chatImage}'
                                            : message.text,
                                        maxLines: widget.messageMaxLines,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: primary,
                                          fontSize: 12,
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
            Row(
              children: [
                IconButton(
                  key: const ValueKey('pick-chat-image'),
                  tooltip: s.chatSendImage,
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.enabled && !_busy ? _pickImage : null,
                  icon: Icon(Icons.image_outlined, color: accent, size: 21),
                ),
                Expanded(
                  child: TextField(
                    key: const ValueKey('room-chat-input'),
                    enabled: widget.enabled && !_busy,
                    readOnly: true,
                    showCursor: false,
                    enableInteractiveSelection: false,
                    onTap: widget.onOpenComposer,
                    decoration: InputDecoration(
                      hintText: s.chatInputPlaceholder,
                      isDense: true,
                      filled: true,
                      fillColor: widget.isNight
                          ? const Color(0xFF121B2B)
                          : const Color(0xFFF1ECE5),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('open-chat-composer'),
                  tooltip: s.viewAllMessages,
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.enabled && !_busy
                      ? widget.onOpenComposer
                      : null,
                  icon: Icon(
                    Icons.open_in_full_rounded,
                    color: accent,
                    size: 19,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
