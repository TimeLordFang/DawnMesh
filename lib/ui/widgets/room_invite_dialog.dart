import 'package:flutter/material.dart';

import '../../core/security/room_invite.dart';
import 'room_invite_code_field.dart';

Future<RoomInvite?> requestRoomInvite(
  BuildContext context, {
  bool creating = false,
}) => showDialog<RoomInvite>(
  context: context,
  builder: (_) => _InviteDialog(creating: creating),
);

class _InviteDialog extends StatefulWidget {
  const _InviteDialog({required this.creating});
  final bool creating;
  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  late final controller = TextEditingController(
    text: widget.creating ? RoomInvite.generate().code : null,
  );
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
    title: Text(widget.creating ? '设置房间邀请码' : '输入房间邀请码'),
    content: RoomInviteCodeField(
      fieldKey: const ValueKey('room-invite-input'),
      controller: controller,
      creating: widget.creating,
      autofocus: true,
      errorText: error,
      onSubmitted: (_) => submit(),
      onRandomized: () => setState(() => error = null),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: submit,
        child: Text(widget.creating ? '创建房间' : '验证并加入'),
      ),
    ],
  );
}
