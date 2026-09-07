import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/security/room_invite.dart';

Future<RoomInvite?> requestRoomInvite(BuildContext context) =>
    showDialog<RoomInvite>(
      context: context,
      builder: (_) => const _InviteDialog(),
    );

Future<void> showRoomInvite(BuildContext context, RoomInvite invite) =>
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('房间邀请码'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  invite.code,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 20),
                ),
                const SizedBox(height: 16),
                const Text('仅分享给信任的人。持有邀请码的人可以加入、收听并查看房内消息；重新建房会更换邀请码。'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: invite.code));
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: const Text('复制邀请码'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('关闭'),
              ),
            ],
          ),
    );

class _InviteDialog extends StatefulWidget {
  const _InviteDialog();
  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final controller = TextEditingController();
  String? error;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    try {
      Navigator.pop(context, RoomInvite.parse(controller.text));
    } on FormatException catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('输入房间邀请码'),
    content: TextField(
      key: const ValueKey('room-invite-input'),
      controller: controller,
      autofocus: true,
      autocorrect: false,
      enableSuggestions: false,
      obscureText: true,
      maxLength: 22,
      onSubmitted: (_) => submit(),
      decoration: InputDecoration(labelText: '房主提供的 22 位邀请码', errorText: error),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(onPressed: submit, child: const Text('验证并加入')),
    ],
  );
}
