import 'package:flutter/material.dart';

/// Makes appearance available from every route, including public rooms.
class AppAppearance extends InheritedWidget {
  const AppAppearance({
    super.key,
    required this.mode,
    required this.onChanged,
    required super.child,
  });
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  static AppAppearance? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppAppearance>();

  @override
  bool updateShouldNotify(AppAppearance oldWidget) => mode != oldWidget.mode;
}
