import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/security/room_invite.dart';

/// The same numeric input and trailing randomize action for all room types.
class RoomInviteCodeField extends StatelessWidget {
  const RoomInviteCodeField({
    super.key,
    required this.controller,
    required this.creating,
    this.fieldKey,
    this.errorText,
    this.autofocus = false,
    this.onSubmitted,
    this.onRandomized,
  });

  final TextEditingController controller;
  final bool creating;
  final Key? fieldKey;
  final String? errorText;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onRandomized;

  @override
  Widget build(BuildContext context) => TextField(
    key: fieldKey,
    controller: controller,
    autofocus: autofocus,
    autocorrect: false,
    enableSuggestions: false,
    maxLength: 4,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    onSubmitted: onSubmitted,
    decoration: InputDecoration(
      labelText: '4 位数字邀请码',
      helperText: creating ? '可手动输入，也可随机生成。' : null,
      helperMaxLines: 2,
      errorText: errorText,
      suffixIcon: creating
          ? IconButton(
              key: const ValueKey('randomize-room-invite'),
              tooltip: '随机生成',
              icon: const Icon(Icons.refresh_rounded, size: 22),
              onPressed: () {
                controller.text = RoomInvite.generate().code;
                controller.selection = TextSelection.collapsed(
                  offset: controller.text.length,
                );
                onRandomized?.call();
              },
            )
          : null,
    ),
  );
}
