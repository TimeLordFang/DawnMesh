import 'package:flutter/material.dart';

import '../../core/internet/internet_models.dart';
import '../../core/internet/server_profile_store.dart';
import '../../l10n/app_strings.dart';
import '../widgets/server_profile_dialog.dart';
import '../widgets/dialog_action_button.dart';

class ServerSettingsPage extends StatefulWidget {
  const ServerSettingsPage({super.key, this.lockedServerId});
  final String? lockedServerId;
  @override
  State<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends State<ServerSettingsPage> {
  final _store = ServerProfileStore();
  List<ServerProfile> _profiles = [];
  String? _selected;
  bool _busy = true;
  String? _error;

  String tr(String zh, String en) => AppStrings.of(context).isEn ? en : zh;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profiles = await _store.loadProfiles();
      final selected = await _store.loadSelectedId();
      if (mounted) {
        setState(() {
          _profiles = profiles;
          _selected = selected;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = tr(
            '无法读取服务器配置，请重试',
            'Could not load servers. Please retry.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([ServerProfile? existing]) async {
    if (_busy || existing != null && existing.id == widget.lockedServerId) {
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await showDialog<ServerProfile>(
        context: context,
        builder: (_) => ServerProfileDialog(existing: existing),
      );
      if (result == null) return;
      final profiles = existing == null
          ? [..._profiles, result]
          : _profiles.map((p) => p.id == existing.id ? result : p).toList();
      await _store.saveProfiles(profiles);
      // Changing saved configuration must not switch an active call's server.
      if (widget.lockedServerId == null) await _store.saveSelectedId(result.id);
      await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = tr('配置保存失败，请重试', 'Could not save server. Please retry.'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(ServerProfile profile) async {
    if (_busy || profile.id == widget.lockedServerId) return;
    setState(() => _busy = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('删除服务器？', 'Remove server?')),
          content: Text(
            tr(
              '从本机移除“${profile.name}”及其访问凭证。',
              'Remove “${profile.name}” and its access credential from this device.',
            ),
          ),
          actions: [
            DialogActionButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('取消', 'Cancel')),
            ),
            DialogActionButton.destructive(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('删除', 'Remove')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final remaining = _profiles.where((p) => p.id != profile.id).toList();
      await _store.saveProfiles(remaining);
      if (_selected == profile.id && remaining.isNotEmpty) {
        await _store.saveSelectedId(remaining.first.id);
      }
      await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = tr('删除失败，请重试', 'Could not remove server. Please retry.'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('服务器', 'Servers'))),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            tr(
              '地址和访问凭证仅保存在这台设备的安全存储中。',
              'Addresses and credentials are saved only in secure storage on this device.',
            ),
          ),
          const SizedBox(height: 16),
          if (widget.lockedServerId != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                tr(
                  '通话中的服务器在结束通话后才能编辑或删除。',
                  'End the active call before editing or removing its server.',
                ),
              ),
            ),
          if (_busy && ModalRoute.of(context)?.isCurrent == true)
            const LinearProgressIndicator(),
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              onPressed: _busy ? null : _load,
              child: Text(tr('重试', 'Retry')),
            ),
          ],
          for (final profile in _profiles)
            Card(
              child: ListTile(
                key: ValueKey('server-profile-${profile.id}'),
                title: Text(profile.name),
                subtitle: Text(
                  profile.baseUrl,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: ValueKey('edit-server-${profile.id}'),
                      tooltip: tr('编辑', 'Edit'),
                      onPressed: _busy || profile.id == widget.lockedServerId
                          ? null
                          : () => _edit(profile),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      key: ValueKey('delete-server-${profile.id}'),
                      tooltip: tr('删除', 'Remove'),
                      onPressed: _busy || profile.id == widget.lockedServerId
                          ? null
                          : () => _delete(profile),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
              ),
            ),
          if (!_busy && _error == null && _profiles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                tr(
                  '尚未添加服务器；附近通信不需要服务器。',
                  'No servers yet. Nearby communication works without one.',
                ),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('add-server'),
            onPressed: _busy ? null : _edit,
            icon: const Icon(Icons.add_rounded),
            label: Text(tr('添加服务器', 'Add server')),
          ),
        ],
      ),
    ),
  );
}
