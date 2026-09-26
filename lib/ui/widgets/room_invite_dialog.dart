import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/security/room_invite.dart';

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
    content: TextField(
      key: const ValueKey('room-invite-input'),
      controller: controller,
      autofocus: true,
      autocorrect: false,
      enableSuggestions: false,
      obscureText: false,
      maxLength: 6,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onSubmitted: (_) => submit(),
      decoration: InputDecoration(
        labelText: '4 位数字（兼容旧版 6 位）',
        helperText: widget.creating ? '可手动修改；有旧版成员时请设为 6 位。' : null,
        errorText: error,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      if (widget.creating)
        TextButton(
          onPressed: () => setState(() {
            controller.text = RoomInvite.generate().code;
            error = null;
          }),
          child: const Text('随机生成'),
        ),
      TextButton(
        onPressed: submit,
        child: Text(widget.creating ? '创建房间' : '验证并加入'),
      ),
    ],
  );
}
