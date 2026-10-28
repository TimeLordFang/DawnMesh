import 'package:flutter/material.dart';

enum _ActionKind { secondary, primary, destructive }

/// Shared geometry and theme colors for modal actions.
class DialogActionButton extends StatelessWidget {
  const DialogActionButton({
    super.key,
    required this.onPressed,
    required this.child,
  }) : _kind = _ActionKind.secondary;

  const DialogActionButton.primary({
    super.key,
    required this.onPressed,
    required this.child,
  }) : _kind = _ActionKind.primary;

  const DialogActionButton.destructive({
    super.key,
    required this.onPressed,
    required this.child,
  }) : _kind = _ActionKind.destructive;

  final VoidCallback? onPressed;
  final Widget child;
  final _ActionKind _kind;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final secondary = _kind == _ActionKind.secondary;
    final destructive = _kind == _ActionKind.destructive;
    final color = destructive ? colors.error : colors.primary;
    final geometry = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(88, 48)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      side: WidgetStateProperty.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.disabled)
              ? colors.onSurface.withValues(alpha: .12)
              : color.withValues(alpha: secondary ? .55 : 1),
        ),
      ),
    );
    if (secondary) {
      return OutlinedButton(
        style: OutlinedButton.styleFrom(foregroundColor: color).merge(geometry),
        onPressed: onPressed,
        child: child,
      );
    }
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: destructive ? colors.onError : colors.onPrimary,
      ).merge(geometry),
      onPressed: onPressed,
      child: child,
    );
  }
}
