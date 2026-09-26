import 'package:flutter/material.dart';

import '../../core/internet/internet_room_session.dart';

class PresenceAnnouncementsControl extends StatefulWidget {
  const PresenceAnnouncementsControl({super.key, required this.session});
  final InternetRoomSession session;
  @override
  State<PresenceAnnouncementsControl> createState() =>
      _PresenceAnnouncementsControlState();
}

class _PresenceAnnouncementsControlState
    extends State<PresenceAnnouncementsControl> {
  bool _saving = false;
  @override
  Widget build(BuildContext context) {
    final room = widget.session.summary;
    return PopupMenuButton<bool>(
      key: const ValueKey('presence-announcements-control'),
      enabled: !_saving && widget.session.isHost,
      tooltip: '成员离线／退出语音提示：${room.presenceAnnouncementsEnabled ? '开启' : '关闭'}',
      icon: Icon(
        room.presenceAnnouncementsEnabled
            ? Icons.notifications_active_outlined
            : Icons.notifications_off_outlined,
      ),
      constraints: const BoxConstraints(maxWidth: 240),
      itemBuilder: (_) => room.presenceAnnouncementsSupported
          ? [
              CheckedPopupMenuItem(
                value: true,
                checked: room.presenceAnnouncementsEnabled,
                child: const Text('开启语音提示'),
              ),
              CheckedPopupMenuItem(
                value: false,
                checked: !room.presenceAnnouncementsEnabled,
                child: const Text('关闭语音提示'),
              ),
              const PopupMenuItem<bool>(
                enabled: false,
                child: Text(
                  '全房间生效。使用系统离线语音，不可用时播放提示音。',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ]
          : [
              const PopupMenuItem<bool>(
                enabled: false,
                child: Text('请先将服务端升级到 0.2.4 或更新版本'),
              ),
            ],
      onSelected: (enabled) async {
        setState(() => _saving = true);
        try {
          await widget.session.setPresenceAnnouncements(enabled);
        } catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('无法修改提示设置：$error')));
          }
        } finally {
          if (mounted) setState(() => _saving = false);
        }
      },
    );
  }
}
