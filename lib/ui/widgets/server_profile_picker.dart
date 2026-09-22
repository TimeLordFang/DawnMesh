import 'package:flutter/material.dart';

import '../../core/internet/internet_models.dart';
import '../theme/app_theme.dart';

/// Expands beneath its field and pushes page content down instead of covering
/// the title or opening a route detached from the server section.
class ServerProfilePicker extends StatefulWidget {
  const ServerProfilePicker({
    super.key,
    required this.profiles,
    required this.selected,
    required this.onSelected,
    required this.isNight,
    this.enabled = true,
  });

  final List<ServerProfile> profiles;
  final ServerProfile? selected;
  final ValueChanged<ServerProfile> onSelected;
  final bool isNight;
  final bool enabled;

  @override
  State<ServerProfilePicker> createState() => _ServerProfilePickerState();
}

class _ServerProfilePickerState extends State<ServerProfilePicker> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant ServerProfilePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _expanded) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.isNight
        ? AppTheme.nightSkyBlue
        : AppTheme.dawnBurgundy;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          enabled: widget.enabled,
          expanded: _expanded,
          label: '当前服务器：${widget.selected?.name ?? '未选择'}',
          child: InkWell(
            key: const ValueKey('server-profile-picker'),
            onTap: widget.enabled
                ? () => setState(() => _expanded = !_expanded)
                : null,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: '当前服务器',
                prefixIcon: const Icon(Icons.dns_outlined),
                suffixIcon: Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                ),
                enabled: widget.enabled,
              ),
              child: Text(
                widget.selected?.name ?? '选择服务器',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: _expanded
              ? Container(
                  key: const ValueKey('server-options-list'),
                  margin: const EdgeInsets.only(top: 6),
                  constraints: const BoxConstraints(maxHeight: 238),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: accent.withValues(alpha: .22)),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: widget.profiles.length,
                    itemBuilder: (_, index) {
                      final item = widget.profiles[index];
                      final selectedHere = item.id == widget.selected?.id;
                      return Material(
                        color: Colors.transparent,
                        child: ListTile(
                          key: ValueKey('server-option-${item.id}'),
                          dense: true,
                          leading: Icon(Icons.dns_outlined, color: accent),
                          title: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            item.baseUrl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: selectedHere
                              ? Icon(Icons.check_rounded, color: accent)
                              : null,
                          onTap: () {
                            setState(() => _expanded = false);
                            if (!selectedHere) widget.onSelected(item);
                          },
                        ),
                      );
                    },
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
