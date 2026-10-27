import 'package:flutter/material.dart';

import '../../core/session/room_session.dart';
import '../pages/settings_page.dart';

/// One settings destination from the home screen and all room toolbars.
class RoomSettingsButton extends StatelessWidget {
  const RoomSettingsButton({
    super.key,
    required this.items,
    this.listenable,
    this.color,
    this.dismissEvents,
    this.session,
  });
  final List<Widget> Function(BuildContext) items;
  final Listenable? listenable;
  final Color? color;
  final Stream<Object?>? dismissEvents;
  final RoomSession? session;

  @override
  Widget build(BuildContext context) {
    final english = Localizations.localeOf(context).languageCode == 'en';
    return IconButton(
      key: const ValueKey('room-settings-button'),
      tooltip: english ? 'Settings' : '设置',
      icon: Icon(Icons.settings_outlined, color: color),
      onPressed: () async {
        final parentRoute = ModalRoute.of(context);
        final dismiss = dismissEvents?.listen((_) {
          if (context.mounted && parentRoute?.isActive == true) {
            Navigator.of(context)
                .popUntil((route) => identical(route, parentRoute));
          }
        });
        try {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => SettingsPage(
                roomItems: items,
                listenable: listenable,
                session: session,
              ),
            ),
          );
        } finally {
          await dismiss?.cancel();
        }
      },
    );
  }
}
