import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/session/chat_message.dart';
import '../../core/session/device_code.dart';
import '../../core/session/member.dart';
import '../../core/session/room_session.dart';
import '../theme/app_theme.dart';
import '../transitions/stage_choreography.dart';
import '../widgets/audio_controls.dart';
import '../widgets/member_orbit.dart';
import '../widgets/ptt_button.dart';
import '../widgets/recent_messages_strip.dart';
import '../widgets/voice_mode_switch.dart';
import '../../l10n/app_strings.dart';

/// 房间前景：成员轨道、中央对讲盘、底部音频控制条。
///
/// 房名、状态行与返回/诊断按钮压在背景上，由 `SessionStage` 绘制。这里每一块都
/// 套了 [StageEnterItem]，按 [stage] 依次从下方浮上来。
class RoomContent extends StatefulWidget {
  final RoomSession session;
  final bool isNight;

  /// 整段进房转场的 0→1 进度。0.52 之前这里还是空的。
  /// 传的是动画本身而不是当帧的值——每块各自听，子树不用按帧重建。
  final Animation<double> stage;

  final VoidCallback onLeave;
  final VoidCallback? onOpenChat;

  const RoomContent({
    super.key,
    required this.session,
    required this.isNight,
    required this.stage,
    required this.onLeave,
    this.onOpenChat,
  });

  @override
  State<RoomContent> createState() => _RoomContentState();
}

class _RoomContentState extends State<RoomContent> {
  bool _isSpeakerOn = true;
  StreamSubscription<void>? _controls;
  @override
  void initState() {
    super.initState();
    _controls = widget.session.controlsStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controls?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNight = widget.isNight;
    final stage = widget.stage;
    final compactHeight = MediaQuery.sizeOf(context).height < 700;
    // 最近消息进入主界面后，按住说话盘主动收紧，避免挤占文字信息。
    final discSize = (MediaQuery.of(context).size.height * 0.15).clamp(
      94.0,
      166.0,
    );

    return SafeArea(
      top: false,
      child: Column(
        children: [
          SizedBox(height: compactHeight ? 4 : 18),

          // 1. 成员轨道
          StageEnterItem(
            stage: stage,
            index: 0,
            child: StreamBuilder<List<Member>>(
              stream: widget.session.membersStream,
              initialData: widget.session.members,
              builder: (context, snapshot) {
                return MemberOrbit(
                  members: snapshot.data ?? [],
                  isNight: isNight,
                  compact: compactHeight,
                );
              },
            ),
          ),

          StreamBuilder<List<ChatMessage>>(
            stream: widget.session.chatListStream,
            initialData: widget.session.chatMessages,
            builder: (context, snapshot) {
              final messages = snapshot.data ?? const <ChatMessage>[];
              if (messages.isEmpty || widget.onOpenChat == null) {
                return const SizedBox.shrink();
              }
              return StreamBuilder<int>(
                stream: widget.session.unreadChatStream,
                initialData: widget.session.unreadChatCount,
                builder: (context, unreadSnapshot) => Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    compactHeight ? 2 : 5,
                    20,
                    compactHeight ? 5 : 8,
                  ),
                  child: RecentMessagesStrip(
                    messages: [
                      for (final message in messages)
                        RecentMessagePreviewItem(
                          sender: DeviceCode.split(message.senderNickname).$1,
                          text: message.text,
                          isMine: message.isLocal,
                        ),
                    ],
                    unreadCount:
                        unreadSnapshot.data ?? widget.session.unreadChatCount,
                    maxVisible: compactHeight ? 2 : 3,
                    isNight: isNight,
                    onTap: widget.onOpenChat!,
                  ),
                ),
              );
            },
          ),

          const Spacer(),

          Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, compactHeight ? 5 : 8),
            child: VoiceModeSwitch(
              value: widget.session.voiceMode,
              isNight: isNight,
              dense: compactHeight,
              onChanged: widget.session.setVoiceMode,
            ),
          ),
          // Each device selects its own transmit mode; receiving stays enabled.
          StageEnterItem(
            stage: stage,
            index: 1,
            rise: 40,
            fromScale: 0.84,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: widget.session.voiceMode == VoiceMode.automatic
                  ? _buildAutomaticStatus(isNight)
                  : PttButton(
                      key: const ValueKey('push-to-talk-button'),
                      isNight: isNight,
                      size: discSize,
                      isPressed: widget.session.isPttPressed,
                      onStateChanged: (pressed) {
                        setState(() {
                          widget.session.setPtt(pressed);
                        });
                      },
                    ),
            ),
          ),

          const Spacer(),

          // 3. 底部控制条（静音 / 扬声器 / 离开）
          StageEnterItem(
            stage: stage,
            index: 2,
            rise: 36,
            child: AudioControlsBar(
              isNight: isNight,
              isMuted: widget.session.isMuted,
              isSpeakerOn: _isSpeakerOn,
              useBuiltinMic: widget.session.useBuiltinMic,
              onToggleMute: () {
                setState(() {
                  widget.session.toggleMute();
                });
              },
              onToggleSpeaker: () {
                setState(() {
                  _isSpeakerOn = !_isSpeakerOn;
                  widget.session.setSpeakerphone(_isSpeakerOn);
                });
              },
              onToggleMicSource: () {
                setState(() {
                  widget.session.setUseBuiltinMic(
                    !widget.session.useBuiltinMic,
                  );
                });
              },
              onLeave: widget.onLeave,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutomaticStatus(bool isNight) {
    final s = AppStrings.of(context);
    final activeColor = isNight ? AppTheme.nightSkyBlue : AppTheme.dawnBurgundy;
    return StreamBuilder<double>(
      key: const ValueKey('automatic-talk-status'),
      stream: widget.session.waveStream,
      initialData: 0.0,
      builder: (context, snapshot) {
        final wave = (snapshot.data ?? 0.0).clamp(0.0, 1.0);
        final isSpeaking = wave > 0.05 && !widget.session.isMuted;
        return Container(
          constraints: const BoxConstraints(maxWidth: 310),
          margin: const EdgeInsets.symmetric(horizontal: 34),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: activeColor.withValues(alpha: isNight ? .22 : .12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: activeColor.withValues(alpha: .35)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.session.isMuted
                    ? Icons.mic_off_rounded
                    : (isSpeaking
                          ? Icons.graphic_eq_rounded
                          : Icons.hearing_rounded),
                size: 22,
                color: activeColor,
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  widget.session.isMuted
                      ? s.micMutedStatus
                      : (isSpeaking ? s.speakingStatus : s.automaticListening),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isNight
                        ? AppTheme.darkTextPrimary
                        : AppTheme.lightTextPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
