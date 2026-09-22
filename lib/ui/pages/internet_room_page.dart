import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/internet/internet_audio_profile.dart';
import '../../core/internet/internet_models.dart';
import '../../core/internet/internet_room_session.dart';
import '../../core/platform/chat_media_service.dart';
import '../../core/session/device_code.dart';
import '../../core/session/room_session.dart' show VoiceMode;
import '../../l10n/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/audio_controls.dart';
import '../widgets/avatar_frame.dart';
import '../widgets/chat_image_bubble.dart';
import '../widgets/room_chat_dock.dart';
import '../widgets/voice_mode_switch.dart';

class InternetRoomPage extends StatefulWidget {
  const InternetRoomPage({
    super.key,
    required this.session,
    required this.isNight,
  });

  final InternetRoomSession session;
  final bool isNight;

  @override
  State<InternetRoomPage> createState() => _InternetRoomPageState();
}

class _InternetRoomPageState extends State<InternetRoomPage>
    with WidgetsBindingObserver {
  bool _inviteVisible = true;
  String? _shownInviteCode;
  Timer? _inviteTimer;
  bool _roomEndedNoticeShown = false;
  bool _exiting = false;
  final _chatMedia = ChatMediaService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.addListener(_onSessionChanged);
    _shownInviteCode = widget.session.hostInviteCode;
    _inviteVisible = _shownInviteCode != null;
    _scheduleInviteHide();
    if (widget.session.roomEnded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showRoomEndedNotice();
      });
    }
  }

  void _scheduleInviteHide() {
    _inviteTimer?.cancel();
    if (!_inviteVisible || _shownInviteCode == null) return;
    _inviteTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _inviteVisible = false);
    });
  }

  void _toggleInvite() {
    setState(() => _inviteVisible = !_inviteVisible);
    _scheduleInviteHide();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(widget.session.setPtt(false));
      _inviteTimer?.cancel();
      if (_inviteVisible) setState(() => _inviteVisible = false);
    }
  }

  void _onSessionChanged() {
    if (!mounted) return;
    if (widget.session.roomEnded) {
      _showRoomEndedNotice();
      setState(() {});
      return;
    }
    final nextCode = widget.session.hostInviteCode;
    if (nextCode != _shownInviteCode) {
      setState(() {
        _shownInviteCode = nextCode;
        // 新房主获得邀请码时显示 10 秒；旧房主失去身份后立即移除。
        _inviteVisible = nextCode != null;
      });
      _scheduleInviteHide();
      return;
    }
    setState(() {});
  }

  void _showRoomEndedNotice() {
    if (_roomEndedNoticeShown || !mounted) return;
    _roomEndedNoticeShown = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        content: Text(
          widget.session.isHost ? '房间已解散，消息会保留到你退出房间' : '房间已被群主解散，消息会保留到你退出房间',
        ),
      ),
    );
  }

  Future<void> _exitRoom() async {
    if (_exiting || !mounted) return;
    _exiting = true;
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    await widget.session.disposeSession();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_onSessionChanged);
    _inviteTimer?.cancel();
    super.dispose();
  }

  Future<void> _leave() async {
    if (widget.session.roomEnded) {
      await _exitRoom();
      return;
    }
    var endRoom = false;
    if (widget.session.isHost) {
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('离开网络房间'),
          content: const Text('保留房间时，在线成员可以继续通话；你的房主身份会按建房时设置的时长保留。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'leave'),
              child: const Text('仅离开'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'end'),
              child: const Text('解散房间'),
            ),
          ],
        ),
      );
      if (action == null) return;
      endRoom = action == 'end';
    }
    try {
      if (endRoom) {
        await widget.session.endRoom();
      } else {
        await widget.session.leave();
        if (mounted) Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) _showError('$error');
    }
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: widget.session.summary.name);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改房间名'),
        content: TextField(
          controller: controller,
          maxLength: 80,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value == null || value.isEmpty) return;
    try {
      await widget.session.renameRoom(value);
    } catch (error) {
      if (mounted) _showError('$error');
    }
  }

  void _showMembers() => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _MemberSheet(
      session: widget.session,
      isNight: widget.isNight,
      accent: widget.isNight ? AppTheme.nightSkyBlue : AppTheme.dawnBurgundy,
    ),
  );

  Future<void> _showChat({bool autofocusComposer = false}) async {
    widget.session.markChatRead();
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _InternetChatSheet(
        session: widget.session,
        autofocusComposer: autofocusComposer,
      ),
    );
    widget.session.markChatRead();
  }

  void _minimize() {
    _dismissKeyboard();
    unawaited(widget.session.setPtt(false));
    Navigator.of(context).pop(false);
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
  }

  void _showError(String value) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(value), backgroundColor: Colors.redAccent),
  );

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final inviteCode = session.hostInviteCode;
    final accent = widget.isNight
        ? AppTheme.nightSkyBlue
        : AppTheme.dawnBurgundy;
    final compactHeight = MediaQuery.sizeOf(context).height < 720;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final stateText = session.roomEnded
        ? '房间已解散 · 消息暂存中'
        : switch (session.connectionState) {
            InternetConnectionState.connecting => '正在安全连接',
            InternetConnectionState.connected => '网络良好 · E2EE',
            InternetConnectionState.reconnecting => '网络波动 · 自动恢复中',
            InternetConnectionState.disconnected => '连接未能恢复',
          };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (keyboardOpen) {
          _dismissKeyboard();
        } else {
          _minimize();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: keyboardOpen ? 48 : 58,
          leading: IconButton(
            tooltip: '返回房间列表（保持通话）',
            onPressed: _minimize,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.summary.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: keyboardOpen ? 17 : 19),
              ),
              if (!keyboardOpen)
                Text(
                  '$stateText · ${session.audioProfile.label} ${session.audioBitrate ~/ 1000}k',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: session.roomEnded
                        ? Colors.redAccent
                        : session.connectionState ==
                              InternetConnectionState.connected
                        ? Colors.green
                        : Colors.orange,
                  ),
                ),
            ],
          ),
          actions: [
            if (!keyboardOpen && session.isHost && !session.roomEnded)
              IconButton(
                tooltip: '修改房间名',
                onPressed: _rename,
                icon: const Icon(Icons.edit_outlined),
              ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              compactHeight ? 6 : 12,
              18,
              compactHeight ? 10 : 20,
            ),
            child: Column(
              children: [
                if (!keyboardOpen && !session.roomEnded && inviteCode != null)
                  _InviteCard(
                    code: inviteCode,
                    visible: _inviteVisible,
                    onToggle: _toggleInvite,
                  ),
                if (!keyboardOpen &&
                    !session.roomEnded &&
                    session.adminListening)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: .35),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.hearing_rounded, color: Colors.orange),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '服务器管理员正在实时收听本房间',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                SizedBox(height: keyboardOpen ? 0 : (compactHeight ? 4 : 8)),
                if (!keyboardOpen && !session.roomEnded)
                  SizedBox(
                    height: compactHeight
                        ? (session.isHost ? 68 : 58)
                        : (session.isHost ? 96 : 76),
                    child: _InternetMemberStrip(
                      session: session,
                      accent: accent,
                      isNight: widget.isNight,
                      onMore: _showMembers,
                      onError: _showError,
                    ),
                  ),
                if (keyboardOpen && !session.roomEnded) const Spacer(),
                if (!keyboardOpen && !session.isHost)
                  Expanded(child: _buildChatDock(session, compactHeight))
                else
                  _buildChatDock(session, compactHeight),
                if (!keyboardOpen && session.isHost) const Spacer(),
                if (!keyboardOpen && !session.isHost && !session.roomEnded)
                  SizedBox(height: compactHeight ? 5 : 8),
                if (!keyboardOpen &&
                    !session.canSpeak &&
                    !session.roomEnded) ...[
                  const Icon(
                    Icons.mic_off_rounded,
                    size: 36,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '房主已关闭你的麦克风',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 22),
                ],
                if (!keyboardOpen && session.roomEnded) ...[
                  const SizedBox(height: 8),
                  Icon(
                    Icons.call_end_rounded,
                    size: 25,
                    color: Colors.redAccent,
                  ),
                  Text(
                    session.isHost ? '房间已解散' : '房间已被群主解散',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Text('聊天记录会保留到退出房间'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    key: const ValueKey('exit-ended-internet-room'),
                    onPressed: _exitRoom,
                    icon: const Icon(Icons.exit_to_app_rounded),
                    label: const Text('退出房间'),
                  ),
                ] else if (!keyboardOpen) ...[
                  VoiceModeSwitch(
                    value: session.voiceMode,
                    isNight: widget.isNight,
                    dense: compactHeight,
                    onChanged: session.canSpeak
                        ? (value) => unawaited(session.setVoiceMode(value))
                        : (_) {},
                  ),
                  SizedBox(height: compactHeight ? 10 : 16),
                  if (session.voiceMode == VoiceMode.pushToTalk)
                    _InternetPttButton(
                      key: const ValueKey('internet-ptt-button'),
                      session: session,
                      accent: accent,
                      size: compactHeight ? 90 : 148,
                    )
                  else
                    _AutomaticTalkStatus(session: session, accent: accent),
                ],
                if (!keyboardOpen && session.isHost) const Spacer(),
                if (!keyboardOpen && !session.isHost && !session.roomEnded)
                  SizedBox(height: compactHeight ? 7 : 10),
                if (!keyboardOpen && !session.roomEnded)
                  RoomControlsBar(
                    key: const ValueKey('internet-room-controls'),
                    compact: true,
                    children: [
                      RoomControlButton(
                        icon: session.isMuted || !session.canSpeak
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded,
                        label: session.isMuted || !session.canSpeak
                            ? '静音'
                            : AppStrings.of(context).microphone,
                        isNight: widget.isNight,
                        onTap: session.canSpeak
                            ? () => unawaited(session.toggleMute())
                            : null,
                        bgColor: widget.isNight
                            ? AppTheme.darkCardBg
                            : AppTheme.lightCardBg,
                        textColor: widget.isNight
                            ? AppTheme.darkTextPrimary
                            : AppTheme.lightTextPrimary,
                        compact: true,
                      ),
                      RoomControlButton(
                        icon: session.isSpeakerOn
                            ? Icons.volume_up_rounded
                            : Icons.phone_in_talk_rounded,
                        label: session.isSpeakerOn
                            ? AppStrings.of(context).speaker
                            : AppStrings.of(context).earpiece,
                        isNight: widget.isNight,
                        onTap: () => unawaited(
                          session.setSpeakerphone(!session.isSpeakerOn),
                        ),
                        bgColor: widget.isNight
                            ? AppTheme.darkCardBg
                            : AppTheme.lightCardBg,
                        textColor: widget.isNight
                            ? AppTheme.darkTextPrimary
                            : AppTheme.lightTextPrimary,
                        compact: true,
                      ),
                      _InternetAudioProfileMenu(
                        key: const ValueKey('internet-audio-profile-button'),
                        session: session,
                        isNight: widget.isNight,
                        accent: accent,
                      ),
                      RoomControlButton(
                        icon: Icons.call_end_rounded,
                        label: AppStrings.of(context).hangUp,
                        isNight: widget.isNight,
                        onTap: _leave,
                        bgColor:
                            (widget.isNight
                                    ? AppTheme.darkLeaveRosePink
                                    : AppTheme.lightLeaveAccent)
                                .withValues(alpha: .15),
                        borderColor:
                            (widget.isNight
                                    ? AppTheme.darkLeaveRosePink
                                    : AppTheme.lightLeaveAccent)
                                .withValues(alpha: .62),
                        textColor: widget.isNight
                            ? AppTheme.darkLeaveRosePink
                            : AppTheme.lightLeaveAccent,
                        compact: true,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatDock(InternetRoomSession session, bool compactHeight) =>
      Padding(
        key: const ValueKey('internet-room-chat-dock-slot'),
        padding: EdgeInsets.only(
          top: compactHeight ? 2 : 5,
          bottom: compactHeight ? 4 : 7,
        ),
        child: RoomChatDock(
          key: const ValueKey('internet-room-chat-dock-widget'),
          margin: EdgeInsets.zero,
          messages: [
            for (final message in session.messages)
              RoomChatDockItem(
                sender: DeviceCode.split(message.senderName).$1,
                text: message.text,
                isMine: message.isMine,
                hasImage: message.hasImage,
              ),
          ],
          isNight: widget.isNight,
          unreadCount: session.unreadChatCount,
          visibleMessageCount:
              !session.isHost && MediaQuery.viewInsetsOf(context).bottom == 0
              ? (compactHeight ? 8 : 14)
              : session.voiceMode == VoiceMode.automatic
              ? (compactHeight ? 4 : 6)
              : (compactHeight ? 2 : 3),
          messageMaxLines:
              session.voiceMode == VoiceMode.automatic || !compactHeight
              ? 2
              : 1,
          compact: compactHeight,
          expandedPreview: session.voiceMode == VoiceMode.automatic,
          fillAvailableSpace:
              !session.isHost && MediaQuery.viewInsetsOf(context).bottom == 0,
          enabled: !session.roomEnded,
          onOpenHistory: _showChat,
          onOpenComposer: () => _showChat(autofocusComposer: true),
          onPickImage: () async {
            final image = await _chatMedia.pickImage();
            if (image == null) return;
            await session.sendChatImage(
              bytes: image.bytes,
              mimeType: image.mimeType,
              name: image.name,
            );
          },
        ),
      );
}

IconData _audioProfileIcon(InternetAudioProfile profile) => switch (profile) {
  InternetAudioProfile.clarity => Icons.high_quality_rounded,
  InternetAudioProfile.balanced => Icons.tune_rounded,
  InternetAudioProfile.dataSaver => Icons.data_saver_on_rounded,
};

class _InternetAudioProfileMenu extends StatelessWidget {
  const _InternetAudioProfileMenu({
    super.key,
    required this.session,
    required this.isNight,
    required this.accent,
  });

  final InternetRoomSession session;
  final bool isNight;
  final Color accent;

  @override
  Widget build(BuildContext context) => PopupMenuButton<InternetAudioProfile>(
    tooltip: '语音质量',
    position: PopupMenuPosition.over,
    offset: const Offset(0, -212),
    constraints: const BoxConstraints(minWidth: 238, maxWidth: 280),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    onSelected: (profile) => unawaited(session.setAudioProfile(profile)),
    itemBuilder: (context) => [
      for (final profile in InternetAudioProfile.values)
        PopupMenuItem<InternetAudioProfile>(
          key: ValueKey('audio-profile-${profile.name}'),
          value: profile,
          child: Row(
            children: [
              Icon(_audioProfileIcon(profile), color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${profile.label} · ${profile.bitrateFor(metered: session.isMeteredNetwork) ~/ 1000}kbps',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      profile.description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (profile == session.audioProfile)
                Icon(Icons.check_rounded, color: accent),
            ],
          ),
        ),
    ],
    child: RoomControlButton(
      icon: _audioProfileIcon(session.audioProfile),
      label: '音质',
      isNight: isNight,
      onTap: null,
      bgColor: isNight ? AppTheme.darkCardBg : AppTheme.lightCardBg,
      textColor: isNight ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
      compact: true,
    ),
  );
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.code,
    required this.visible,
    required this.onToggle,
  });
  final String code;
  final bool visible;
  final VoidCallback onToggle;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.key_rounded),
          const SizedBox(width: 12),
          const Text('邀请码'),
          const Spacer(),
          Text(
            visible ? code : '••••••',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
            ),
          ),
          IconButton(
            tooltip: visible ? '隐藏邀请码' : '显示邀请码',
            onPressed: onToggle,
            icon: Icon(
              visible
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ],
      ),
    ),
  );
}

class _InternetMemberStrip extends StatelessWidget {
  const _InternetMemberStrip({
    required this.session,
    required this.accent,
    required this.isNight,
    required this.onMore,
    required this.onError,
  });

  final InternetRoomSession session;
  final Color accent;
  final bool isNight;
  final VoidCallback onMore;
  final ValueChanged<String> onError;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const itemExtent = 78.0;
      final capacity = (constraints.maxWidth / itemExtent).floor().clamp(1, 12);
      final overflow = session.members.length > capacity;
      final visibleCount = overflow
          ? (capacity - 1).clamp(0, session.members.length)
          : session.members.length;
      return Row(
        mainAxisAlignment: visibleCount < capacity
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          for (final member in session.members.take(visibleCount))
            _MemberPill(
              member: member,
              session: session,
              accent: accent,
              isNight: isNight,
              onError: onError,
            ),
          if (overflow)
            _MoreMembersPill(
              hiddenCount: session.members.length - visibleCount,
              accent: accent,
              onTap: onMore,
            ),
        ],
      );
    },
  );
}

class _MemberPill extends StatelessWidget {
  const _MemberPill({
    required this.member,
    required this.session,
    required this.accent,
    required this.isNight,
    required this.onError,
  });
  final InternetMember member;
  final InternetRoomSession session;
  final Color accent;
  final bool isNight;
  final ValueChanged<String> onError;

  Future<void> _setVoice() async {
    try {
      await session.setMemberCanSpeak(member.id, !member.canSpeak);
    } catch (error) {
      onError('$error');
    }
  }

  Future<void> _transfer(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移交房主'),
        content: Text('确定将房主移交给“${member.nickname}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认移交'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await session.transferHost(member.id);
    } catch (error) {
      onError('$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (displayName, code) = DeviceCode.split(member.nickname);
    final manageable = session.isHost && member.id != session.memberId;
    return SizedBox(
      width: 78,
      child: Column(
        children: [
          AvatarFrame(
            senderCode: code ?? member.id,
            nickname: displayName,
            isHost: member.isHost,
            isSpeaking: member.isSpeaking,
            isMuted: !member.canSpeak,
            size: 48,
            isNight: isNight,
          ),
          const SizedBox(height: 4),
          Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
          if (manageable)
            SizedBox(
              height: 30,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: member.canSpeak ? '关闭麦克风' : '恢复发言',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    onPressed: _setVoice,
                    icon: Icon(
                      member.canSpeak
                          ? Icons.mic_off_rounded
                          : Icons.mic_rounded,
                      color: accent,
                    ),
                  ),
                  IconButton(
                    tooltip: '移交房主',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    onPressed: () => _transfer(context),
                    icon: Icon(Icons.workspace_premium_outlined, color: accent),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MoreMembersPill extends StatelessWidget {
  const _MoreMembersPill({
    required this.hiddenCount,
    required this.accent,
    required this.onTap,
  });
  final int hiddenCount;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 78,
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: accent.withValues(alpha: .14),
            foregroundColor: accent,
            child: const Icon(Icons.more_horiz_rounded),
          ),
          const SizedBox(height: 4),
          Text('更多 $hiddenCount', style: const TextStyle(fontSize: 11)),
        ],
      ),
    ),
  );
}

class _InternetPttButton extends StatelessWidget {
  const _InternetPttButton({
    super.key,
    required this.session,
    required this.accent,
    required this.size,
  });
  final InternetRoomSession session;
  final Color accent;
  final double size;
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: session.canSpeak && !session.isMuted
        ? (_) => unawaited(session.setPtt(true))
        : null,
    onTapUp: (_) => unawaited(session.setPtt(false)),
    onTapCancel: () => unawaited(session.setPtt(false)),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: session.isPttPressed ? accent : accent.withValues(alpha: .88),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: session.isPttPressed ? .48 : .22),
            blurRadius: session.isPttPressed ? 36 : 18,
            spreadRadius: session.isPttPressed ? 8 : 2,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            session.isMuted || !session.canSpeak
                ? Icons.mic_off_rounded
                : Icons.touch_app_rounded,
            size: 48,
            color: Colors.white,
          ),
          const SizedBox(height: 10),
          Text(
            session.isPttPressed ? '正在说话' : '按住说话',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
        ],
      ),
    ),
  );
}

class _AutomaticTalkStatus extends StatelessWidget {
  const _AutomaticTalkStatus({required this.session, required this.accent});
  final InternetRoomSession session;
  final Color accent;
  @override
  Widget build(BuildContext context) => StreamBuilder<double>(
    key: const ValueKey('internet-automatic-talk-status'),
    stream: session.waveStream,
    initialData: 0,
    builder: (_, snapshot) {
      final wave = (snapshot.data ?? 0).clamp(0.0, 1.0);
      final speaking = wave > .05 && !session.isMuted && session.canSpeak;
      return Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withValues(alpha: .32)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              session.isMuted || !session.canSpeak
                  ? Icons.mic_off_rounded
                  : (speaking
                        ? Icons.graphic_eq_rounded
                        : Icons.hearing_rounded),
              size: 22,
              color: accent,
            ),
            const SizedBox(width: 9),
            Text(
              session.isMuted || !session.canSpeak
                  ? '麦克风已关闭'
                  : (speaking ? '正在说话' : '自动通话正在聆听'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    },
  );
}

class _MemberSheet extends StatefulWidget {
  const _MemberSheet({
    required this.session,
    required this.isNight,
    required this.accent,
  });
  final InternetRoomSession session;
  final bool isNight;
  final Color accent;
  @override
  State<_MemberSheet> createState() => _MemberSheetState();
}

class _MemberSheetState extends State<_MemberSheet> {
  @override
  void initState() {
    super.initState();
    widget.session.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.session.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: .65,
    builder: (_, controller) => CustomScrollView(
      controller: controller,
      slivers: [
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, 12),
          sliver: SliverToBoxAdapter(
            child: Text(
              '全部成员',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _MemberPill(
                member: widget.session.members[index],
                session: widget.session,
                accent: widget.accent,
                isNight: widget.isNight,
                onError: (message) =>
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(message))),
              ),
              childCount: widget.session.members.length,
            ),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 96,
              mainAxisExtent: 112,
              crossAxisSpacing: 4,
              mainAxisSpacing: 8,
            ),
          ),
        ),
      ],
    ),
  );
}

class _InternetChatSheet extends StatefulWidget {
  const _InternetChatSheet({
    required this.session,
    this.autofocusComposer = false,
  });
  final InternetRoomSession session;
  final bool autofocusComposer;
  @override
  State<_InternetChatSheet> createState() => _InternetChatSheetState();
}

class _InternetChatSheetState extends State<_InternetChatSheet> {
  final _controller = TextEditingController();
  final _chatMedia = ChatMediaService();
  bool _sending = false;
  @override
  void initState() {
    super.initState();
    widget.session.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.session.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || widget.session.roomEnded) return;
    final text = _controller.text;
    _controller.clear();
    await widget.session.sendChat(text);
  }

  Future<void> _sendImage() async {
    if (_sending || widget.session.roomEnded) return;
    setState(() => _sending = true);
    try {
      final image = await _chatMedia.pickImage();
      if (image == null) return;
      await widget.session.sendChatImage(
        bytes: image.bytes,
        mimeType: image.mimeType,
        name: image.name,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return PopScope(
      canPop: !keyboardOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !keyboardOpen) return;
        FocusManager.instance.primaryFocus?.unfocus();
        unawaited(
          SystemChannels.textInput.invokeMethod<void>('TextInput.hide'),
        );
      },
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .82,
        builder: (_, scroll) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                '加密消息',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: widget.session.messages.isEmpty
                  ? const Center(child: Text('还没人说第一句'))
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: widget.session.messages.length,
                      itemBuilder: (_, index) {
                        final message = widget.session.messages[index];
                        final member = widget.session.members
                            .where((item) => item.id == message.senderId)
                            .firstOrNull;
                        final (senderName, senderCode) = DeviceCode.split(
                          message.senderName,
                        );
                        final avatar = AvatarFrame(
                          senderCode: senderCode ?? message.senderId,
                          nickname: senderName,
                          isHost: member?.isHost ?? false,
                          size: 34,
                          isNight:
                              Theme.of(context).brightness == Brightness.dark,
                        );
                        final bubble = Container(
                          margin: const EdgeInsets.only(bottom: 9),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          constraints: const BoxConstraints(maxWidth: 270),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!message.isMine)
                                Text(
                                  senderName,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              if (message.hasImage)
                                ChatImageBubble(
                                  bytes: message.imageBytes!,
                                  name: message.imageName ?? 'DawnMesh_image',
                                  isMine: message.isMine,
                                )
                              else
                                Text(message.text),
                            ],
                          ),
                        );
                        return Row(
                          mainAxisAlignment: message.isMine
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: message.isMine
                              ? [bubble, const SizedBox(width: 8), avatar]
                              : [avatar, const SizedBox(width: 8), bubble],
                        );
                      },
                    ),
            ),
            if (widget.session.roomEnded)
              const SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('房间已解散 · 可继续查看和保存消息'),
                ),
              )
            else
              SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    14,
                    8,
                    8,
                    MediaQuery.viewInsetsOf(context).bottom + 8,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: '发送图片',
                        onPressed: _sending ? null : _sendImage,
                        icon: const Icon(Icons.image_outlined),
                      ),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('full-chat-input'),
                          controller: _controller,
                          autofocus: widget.autofocusComposer,
                          maxLength: 1000,
                          minLines: 1,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            hintText: '说点什么…',
                            counterText: '',
                          ),
                        ),
                      ),
                      IconButton.filled(
                        key: const ValueKey('full-chat-send'),
                        onPressed: _send,
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
