import 'package:flutter/material.dart';

import '../../core/internet/internet_models.dart';
import '../theme/app_theme.dart';

/// A fixed-position server chooser: the choices live in a bottom sheet, not
/// in a dropdown route that can grow upward over the current page.
class ServerProfilePicker extends StatelessWidget {
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

  Future<void> _open(BuildContext context) async {
    if (!enabled) return;
    final accent = isNight ? AppTheme.nightSkyBlue : AppTheme.dawnBurgundy;
    final profile = await showModalBottomSheet<ServerProfile>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(6, 0, 6, 12),
                child: Text(
                  '切换服务器',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: profiles.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    final item = profiles[index];
                    final selectedHere = item.id == selected?.id;
                    return Material(
                      color: selectedHere
                          ? accent.withValues(alpha: .12)
                          : Theme.of(sheetContext)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: .55),
                      borderRadius: BorderRadius.circular(16),
                      child: ListTile(
                        key: ValueKey('server-option-${item.id}'),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        leading: Icon(Icons.dns_outlined, color: accent),
                        title: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          item.baseUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: selectedHere
                            ? Icon(Icons.check_circle_rounded, color: accent)
                            : null,
                        onTap: () => Navigator.pop(sheetContext, item),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (profile != null && context.mounted && profile.id != selected?.id) {
      onSelected(profile);
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: enabled,
    label: '当前服务器：${selected?.name ?? '未选择'}',
    child: InkWell(
      key: const ValueKey('server-profile-picker'),
      onTap: enabled ? () => _open(context) : null,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: '当前服务器',
          prefixIcon: const Icon(Icons.dns_outlined),
          suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
          enabled: enabled,
        ),
        child: Text(
          selected?.name ?? '选择服务器',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ),
  );
}
