import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/security/room_invite.dart';

Future<RoomInvite?> requestRoomInvite(BuildContext context) =>
    showDialog<RoomInvite>(
      context: context,
      builder: (_) => const _InviteDialog(),
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
      obscureText: false,
      maxLength: 6,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onSubmitted: (_) => submit(),
      decoration: InputDecoration(
        labelText: '房主提供的 6 位数字邀请码',
        errorText: error,
      ),
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
