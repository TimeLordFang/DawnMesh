import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/internet/internet_models.dart';
import '../../core/internet/internet_room_session.dart';
import '../../core/session/room_session.dart' show VoiceMode;
import '../theme/app_theme.dart';
import '../widgets/voice_mode_switch.dart';

class InternetRoomPage extends StatefulWidget {
  const InternetRoomPage({
    super.key,
    required this.session,
    required this.isNight,
    this.inviteCode,
  });

  final InternetRoomSession session;
  final bool isNight;
  final String? inviteCode;

  @override
  State<InternetRoomPage> createState() => _InternetRoomPageState();
}

class _InternetRoomPageState extends State<InternetRoomPage>
    with WidgetsBindingObserver {
  bool _inviteVisible = true;
  Timer? _inviteTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.addListener(_onSessionChanged);
    if (widget.inviteCode != null) {
      _inviteTimer = Timer(const Duration(seconds: 10), () {
        if (mounted) setState(() => _inviteVisible = false);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(widget.session.setPtt(false));
    }
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_onSessionChanged);
    _inviteTimer?.cancel();
    super.dispose();
  }

  Future<void> _leave() async {
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
    await widget.session.leave(endRoom: endRoom);
    if (mounted) Navigator.pop(context);
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
    builder: (_) => _MemberSheet(session: widget.session),
  );

  void _showChat() => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _InternetChatSheet(session: widget.session),
  );

  void _showError(String value) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(value), backgroundColor: Colors.redAccent),
  );

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final accent = widget.isNight
        ? AppTheme.nightSkyBlue
        : AppTheme.dawnBurgundy;
    final stateText = switch (session.connectionState) {
      InternetConnectionState.connecting => '正在安全连接',
      InternetConnectionState.connected => '网络良好 · E2EE',
      InternetConnectionState.reconnecting => '网络波动 · 自动恢复中',
      InternetConnectionState.disconnected => '连接未能恢复',
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: _leave,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.summary.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                stateText,
                style: TextStyle(
                  fontSize: 12,
                  color:
                      session.connectionState ==
                          InternetConnectionState.connected
                      ? Colors.green
                      : Colors.orange,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '成员',
              onPressed: _showMembers,
              icon: Badge(
                label: Text('${session.members.length}'),
                child: const Icon(Icons.group_outlined),
              ),
            ),
            IconButton(
              tooltip: '消息',
              onPressed: _showChat,
              icon: const Icon(Icons.chat_bubble_outline_rounded),
            ),
            if (session.isHost)
              IconButton(
                tooltip: '修改房间名',
                onPressed: _rename,
                icon: const Icon(Icons.edit_outlined),
              ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
            child: Column(
              children: [
                if (widget.inviteCode != null)
                  _InviteCard(
                    code: widget.inviteCode!,
                    visible: _inviteVisible,
                    onToggle: () =>
                        setState(() => _inviteVisible = !_inviteVisible),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 72,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: session.members.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (_, index) {
                      final member = session.members[index];
                      return _MemberPill(member: member, accent: accent);
                    },
                  ),
                ),
                const Spacer(),
                if (!session.canSpeak) ...[
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
                VoiceModeSwitch(
                  value: session.voiceMode,
                  isNight: widget.isNight,
                  onChanged: session.canSpeak
                      ? (value) => unawaited(session.setVoiceMode(value))
                      : (_) {},
                ),
                const SizedBox(height: 24),
                if (session.voiceMode == VoiceMode.pushToTalk)
                  _InternetPttButton(session: session, accent: accent)
                else
                  _AutomaticTalkDisc(session: session, accent: accent),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: .72),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      IconButton.filledTonal(
                        tooltip: session.isMuted ? '开启麦克风' : '静音',
                        onPressed: session.canSpeak
                            ? () => unawaited(session.toggleMute())
                            : null,
                        icon: Icon(
                          session.isMuted || !session.canSpeak
                              ? Icons.mic_off_rounded
                              : Icons.mic_rounded,
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: session.isSpeakerOn ? '切换到听筒/耳机' : '打开扬声器',
                        onPressed: () => unawaited(
                          session.setSpeakerphone(!session.isSpeakerOn),
                        ),
                        icon: Icon(
                          session.isSpeakerOn
                              ? Icons.volume_up_rounded
                              : Icons.hearing_rounded,
                        ),
                      ),
                      IconButton.filled(
                        tooltip: '离开',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _leave,
                        icon: const Icon(Icons.call_end_rounded),
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

class _MemberPill extends StatelessWidget {
  const _MemberPill({required this.member, required this.accent});
  final InternetMember member;
  final Color accent;
  @override
  Widget build(BuildContext context) => Container(
    width: 64,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Column(
      children: [
        CircleAvatar(
          backgroundColor: member.isSpeaking
              ? accent
              : accent.withValues(alpha: .14),
          foregroundColor: member.isSpeaking ? Colors.white : accent,
          child: Icon(
            member.canSpeak ? Icons.person_rounded : Icons.mic_off_rounded,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          member.nickname,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11),
        ),
      ],
    ),
  );
}

class _InternetPttButton extends StatelessWidget {
  const _InternetPttButton({required this.session, required this.accent});
  final InternetRoomSession session;
  final Color accent;
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
      width: 176,
      height: 176,
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

class _AutomaticTalkDisc extends StatelessWidget {
  const _AutomaticTalkDisc({required this.session, required this.accent});
  final InternetRoomSession session;
  final Color accent;
  @override
  Widget build(BuildContext context) => StreamBuilder<double>(
    stream: session.waveStream,
    initialData: 0,
    builder: (_, snapshot) {
      final wave = (snapshot.data ?? 0).clamp(0.0, 1.0);
      return Transform.scale(
        scale: 1 + wave * .06,
        child: Container(
          width: 176,
          height: 176,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent,
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: .36),
                blurRadius: 30,
                spreadRadius: 6,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                session.isMuted || !session.canSpeak
                    ? Icons.mic_off_rounded
                    : Icons.graphic_eq_rounded,
                size: 54,
                color: Colors.white,
              ),
              const SizedBox(height: 8),
              Text(
                session.isMuted ? '麦克风已关闭' : '自动通话中',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _MemberSheet extends StatefulWidget {
  const _MemberSheet({required this.session});
  final InternetRoomSession session;
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
    builder: (_, controller) => ListView(
      controller: controller,
      padding: const EdgeInsets.all(18),
      children: [
        const Text(
          '房间成员',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        for (final member in widget.session.members)
          ListTile(
            leading: CircleAvatar(
              child: Icon(member.canSpeak ? Icons.person : Icons.mic_off),
            ),
            title: Text(member.nickname),
            subtitle: Text(
              member.isHost ? '房主' : (member.canSpeak ? '可发言' : '已被房主禁麦'),
            ),
            trailing:
                widget.session.isHost && member.id != widget.session.memberId
                ? PopupMenuButton<String>(
                    onSelected: (value) async {
                      try {
                        if (value == 'voice') {
                          await widget.session.setMemberCanSpeak(
                            member.id,
                            !member.canSpeak,
                          );
                        }
                        if (value == 'host') {
                          await widget.session.transferHost(member.id);
                        }
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('$error')));
                        }
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'voice',
                        child: Text(member.canSpeak ? '关闭麦克风' : '恢复发言资格'),
                      ),
                      const PopupMenuItem(value: 'host', child: Text('移交房主')),
                    ],
                  )
                : null,
          ),
      ],
    ),
  );
}

class _InternetChatSheet extends StatefulWidget {
  const _InternetChatSheet({required this.session});
  final InternetRoomSession session;
  @override
  State<_InternetChatSheet> createState() => _InternetChatSheetState();
}

class _InternetChatSheetState extends State<_InternetChatSheet> {
  final _controller = TextEditingController();
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
    final text = _controller.text;
    _controller.clear();
    await widget.session.sendChat(text);
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
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
                    return Align(
                      alignment: message.isMine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 9),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        constraints: const BoxConstraints(maxWidth: 300),
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
                                message.senderName,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            Text(message.text),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
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
                Expanded(
                  child: TextField(
                    controller: _controller,
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
                  onPressed: _send,
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
