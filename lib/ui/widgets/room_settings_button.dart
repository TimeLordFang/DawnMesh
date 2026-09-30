import 'package:flutter/material.dart';

/// One toolbar action leaves room names and live connection status readable.
/// Settings live in a scrollable sheet so large text never crowds the header.
class RoomSettingsButton extends StatelessWidget {
  const RoomSettingsButton({
    super.key,
    required this.items,
    this.listenable,
    this.color,
    this.dismissEvents,
  });
  final List<Widget> Function(BuildContext) items;
  final Listenable? listenable;
  final Color? color;
  final Stream<Object?>? dismissEvents;

  @override
  Widget build(BuildContext context) {
    final english = Localizations.localeOf(context).languageCode == 'en';
    return IconButton(
      key: const ValueKey('room-settings-button'),
      tooltip: english ? 'Room settings' : '房间设置',
      icon: Icon(Icons.more_horiz_rounded, color: color),
      onPressed: () async {
        final parentRoute = ModalRoute.of(context);
        final dismiss = dismissEvents?.listen((_) {
          if (context.mounted && parentRoute?.isActive == true) {
            Navigator.of(context)
                .popUntil((route) => identical(route, parentRoute));
          }
        });
        try {
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            constraints: const BoxConstraints(maxWidth: 560),
            builder: (sheetContext) {
              Widget content() => SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              english ? 'Room settings' : '房间设置',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: english ? 'Close' : '关闭',
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      ...items(sheetContext),
                    ],
                  ),
                ),
              );
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(sheetContext).height * .85,
                ),
                child: listenable == null
                    ? content()
                    : AnimatedBuilder(
                        animation: listenable!,
                        builder: (_, _) => content(),
                      ),
              );
            },
          );
        } finally {
          await dismiss?.cancel();
        }
      },
    );
  }
}
