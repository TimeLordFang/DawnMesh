import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/diagnostics/app_log.dart';
import '../../core/internet/internet_models.dart';
import '../../core/internet/internet_room_api.dart';
import '../../core/internet/internet_room_session.dart';
import '../../core/internet/server_profile_store.dart';
import '../../core/security/room_invite.dart';
import '../theme/app_theme.dart';
import '../widgets/room_invite_dialog.dart';
import '../widgets/server_profile_picker.dart';
import 'internet_room_page.dart';

class InternetHomePage extends StatefulWidget {
  const InternetHomePage({
    super.key,
    required this.isNight,
    required this.nickname,
    this.activeSession,
    this.onActiveSessionChanged,
    this.reopenActiveRoom = false,
    this.rememberedInvites,
  });

  final bool isNight;
  final String nickname;
  final InternetRoomSession? activeSession;
  final ValueChanged<InternetRoomSession?>? onActiveSessionChanged;
  final bool reopenActiveRoom;
  final Map<String, RoomInvite>? rememberedInvites;

  @override
  State<InternetHomePage> createState() => _InternetHomePageState();
}

class _InternetHomePageState extends State<InternetHomePage> {
  final _store = ServerProfileStore();
  List<ServerProfile> _profiles = const [];
  ServerProfile? _selected;
  InternetServerInfo? _info;
  List<InternetRoomSummary> _rooms = const [];
  bool _loading = true;
  String? _error;
  InternetRoomSession? _activeSession;
  bool _roomPageOpen = false;
  late final Map<String, RoomInvite> _rememberedInvites;

  String _inviteKey(ServerProfile profile, String roomId) =>
      'internet:${profile.id}:$roomId';

  @override
  void initState() {
    super.initState();
    _rememberedInvites = widget.rememberedInvites ?? <String, RoomInvite>{};
    _activeSession = widget.activeSession;
    _activeSession?.addListener(_onActiveSessionChanged);
    unawaited(_load());
    if (widget.reopenActiveRoom && _activeSession != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openActiveRoom());
      });
    }
  }

  @override
  void dispose() {
    _activeSession?.removeListener(_onActiveSessionChanged);
    super.dispose();
  }

  void _setActiveSession(InternetRoomSession? session) {
    if (identical(_activeSession, session)) return;
    _activeSession?.removeListener(_onActiveSessionChanged);
    _activeSession = session;
    session?.addListener(_onActiveSessionChanged);
    widget.onActiveSessionChanged?.call(session);
    if (mounted) setState(() {});
  }

  void _onActiveSessionChanged() {
    final session = _activeSession;
    if (!mounted || session == null) return;
    if (session.roomEnded) {
      if (_roomPageOpen) return;
      _rememberedInvites.remove(_inviteKey(session.profile, session.roomId));
      _setActiveSession(null);
      unawaited(session.disposeSession());
      if (!session.isHost) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('房间已被群主解散，已从进入记录中移除')));
      }
      unawaited(_refresh());
      return;
    }
    setState(() {});
  }

  Future<void> _load() async {
    final profiles = await _store.loadProfiles();
    final selectedId = await _store.loadSelectedId();
    final selected =
        profiles.where((item) => item.id == selectedId).firstOrNull ??
        profiles.firstOrNull;
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _selected = selected;
      _loading = false;
    });
    if (selected != null) await _refresh();
  }

  Future<void> _refresh() async {
    final profile = _selected;
    if (profile == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = InternetRoomApi(profile);
    try {
      final results = await Future.wait<dynamic>([api.info(), api.rooms()]);
      final info = results[0] as InternetServerInfo;
      if (info.protocolVersion != 1) {
        throw InternetApiException(
          '服务器协议版本 ${info.protocolVersion} 与当前 App 不兼容',
        );
      }
      if (profile.instanceId != null && profile.instanceId != info.instanceId) {
        throw const InternetApiException('服务器实例标识发生变化，请编辑服务器并重新确认');
      }
      final updated = profile.copyWith(
        name: profile.name.isEmpty ? info.name : profile.name,
        instanceId: info.instanceId,
      );
      final profiles = _profiles
          .map((item) => item.id == updated.id ? updated : item)
          .toList();
      await _store.saveProfiles(profiles);
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _selected = updated;
        _info = info;
        _rooms = results[1] as List<InternetRoomSummary>;
        final aliveInviteKeys = _rooms
            .map((room) => _inviteKey(updated, room.id))
            .toSet();
        if (_activeSession != null) {
          aliveInviteKeys.add(
            _inviteKey(_activeSession!.profile, _activeSession!.roomId),
          );
        }
        final profilePrefix = 'internet:${updated.id}:';
        _rememberedInvites.removeWhere(
          (key, _) =>
              key.startsWith(profilePrefix) && !aliveInviteKeys.contains(key),
        );
      });
    } catch (error, stack) {
      AppLog.error('DawnInternet', '连接服务器失败：$error', stack);
      if (mounted) setState(() => _error = '$error');
    } finally {
      api.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editProfile({ServerProfile? existing}) async {
    final result = await showDialog<ServerProfile>(
      context: context,
      builder: (_) => _ServerProfileDialog(existing: existing),
    );
    if (result == null) return;
    final profiles = existing == null
        ? [..._profiles, result]
        : _profiles
              .map((item) => item.id == existing.id ? result : item)
              .toList();
    await _store.saveProfiles(profiles);
    await _store.saveSelectedId(result.id);
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _selected = result;
      _info = null;
      _rooms = const [];
    });
    await _refresh();
  }

  Future<void> _deleteSelected() async {
    final selected = _selected;
    if (selected == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除服务器？'),
        content: Text('将从本机移除“${selected.name}”及其访问凭证。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final profiles = _profiles.where((item) => item.id != selected.id).toList();
    final next = profiles.firstOrNull;
    await _store.saveProfiles(profiles);
    if (next != null) await _store.saveSelectedId(next.id);
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _selected = next;
      _info = null;
      _rooms = const [];
    });
    if (next != null) await _refresh();
  }

  Future<void> _selectProfile(ServerProfile? profile) async {
    if (profile == null || profile.id == _selected?.id) return;
    await _store.saveSelectedId(profile.id);
    setState(() {
      _selected = profile;
      _info = null;
      _rooms = const [];
    });
    await _refresh();
  }

  Future<void> _createRoom() async {
    final profile = _selected;
    final info = _info;
    if (profile == null || info == null) return;
    final options = await showDialog<_CreateOptions>(
      context: context,
      builder: (_) => _CreateRoomDialog(
        initialName: '${widget.nickname}的网络聊天室',
        serverMaximum: info.maxRoomParticipants,
        adminListeningSupported: info.adminListeningSupported,
      ),
    );
    if (options == null) return;
    final invite = RoomInvite.generate();
    final api = InternetRoomApi(profile);
    _showBusy('正在创建安全房间…');
    try {
      final session = await InternetRoomSession.create(
        api: api,
        profile: profile,
        nickname: widget.nickname,
        deviceId: await _store.deviceId(),
        roomName: options.name,
        maxParticipants: options.maxParticipants,
        hostDisconnectTimeoutMinutes: options.hostTimeoutMinutes,
        invite: invite,
        allowAdminListening: options.allowAdminListening,
      );
      if (!mounted) {
        await session.disposeSession();
        return;
      }
      Navigator.pop(context);
      _rememberedInvites[_inviteKey(profile, session.roomId)] = invite;
      _setActiveSession(session);
      await _openActiveRoom();
    } catch (error, stack) {
      api.close();
      AppLog.error('DawnInternet', '创建公网房失败：$error', stack);
      if (mounted) {
        Navigator.pop(context);
        _showError('$error');
      }
    }
  }

  Future<void> _joinRoom(InternetRoomSummary room) async {
    final active = _activeSession;
    if (active != null) {
      if (active.roomId == room.id) await _openActiveRoom();
      return;
    }
    final profile = _selected;
    if (profile == null) return;
    final inviteKey = _inviteKey(profile, room.id);
    final invite =
        _rememberedInvites[inviteKey] ?? await requestRoomInvite(context);
    if (invite == null || !mounted) return;
    final api = InternetRoomApi(profile);
    _showBusy('正在由房主验证邀请码…');
    try {
      final session = await InternetRoomSession.join(
        api: api,
        profile: profile,
        nickname: widget.nickname,
        deviceId: await _store.deviceId(),
        room: room,
        invite: invite,
      );
      if (!mounted) {
        await session.disposeSession();
        return;
      }
      Navigator.pop(context);
      _rememberedInvites[inviteKey] = invite;
      _setActiveSession(session);
      await _openActiveRoom();
    } catch (error, stack) {
      _rememberedInvites.remove(inviteKey);
      api.close();
      AppLog.error('DawnInternet', '加入公网房失败：$error', stack);
      if (mounted) {
        Navigator.pop(context);
        _showError('$error');
      }
    }
  }

  Future<void> _openActiveRoom() async {
    final session = _activeSession;
    if (session == null || !mounted || _roomPageOpen) return;
    setState(() => _roomPageOpen = true);
    final ended = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            InternetRoomPage(session: session, isNight: widget.isNight),
      ),
    );
    if (!mounted) return;
    setState(() => _roomPageOpen = false);
    if (!identical(_activeSession, session)) return;
    if (ended == true || session.roomEnded) {
      if (session.roomEnded) {
        _rememberedInvites.remove(_inviteKey(session.profile, session.roomId));
      }
      _setActiveSession(null);
      await session.disposeSession();
      if (mounted) await _refresh();
    }
  }

  void _showBusy(String message) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );

  void _showError(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
  );

  @override
  Widget build(BuildContext context) {
    final accent = widget.isNight
        ? AppTheme.nightSkyBlue
        : AppTheme.dawnBurgundy;
    return Scaffold(
      appBar: AppBar(
        title: const Text('网络对讲'),
        actions: [
          if (_selected != null) ...[
            IconButton(
              tooltip: '编辑服务器',
              onPressed: _activeSession == null
                  ? () => _editProfile(existing: _selected)
                  : null,
              icon: const Icon(Icons.edit_outlined),
            ),
            PopupMenuButton<String>(
              enabled: _activeSession == null,
              onSelected: (value) {
                if (value == 'add') _editProfile();
                if (value == 'delete') _deleteSelected();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'add', child: Text('添加服务器')),
                PopupMenuItem(value: 'delete', child: Text('删除当前服务器')),
              ],
            ),
          ],
        ],
      ),
      floatingActionButton: _info == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _loading || _activeSession != null
                  ? null
                  : _createRoom,
              backgroundColor: accent,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('创建房间'),
            ),
      body: _profiles.isEmpty
          ? _emptyServers(accent)
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 104),
                children: [
                  if (_activeSession != null) ...[
                    _ActiveInternetRoomCard(
                      session: _activeSession!,
                      accent: accent,
                      onResume: _openActiveRoom,
                    ),
                    const SizedBox(height: 12),
                  ],
                  ServerProfilePicker(
                    profiles: _profiles,
                    selected: _selected,
                    isNight: widget.isNight,
                    enabled: !_loading && _activeSession == null,
                    onSelected: _selectProfile,
                  ),
                  const SizedBox(height: 12),
                  if (_loading) const LinearProgressIndicator(),
                  if (_error != null)
                    _statusCard(
                      Icons.cloud_off_outlined,
                      '连接失败',
                      _error!,
                      Colors.redAccent,
                    ),
                  if (_info != null)
                    _statusCard(
                      Icons.verified_user_outlined,
                      '连接正常 · ${_info!.name}',
                      '协议 v${_info!.protocolVersion} · 房间上限 ${_info!.maxRoomParticipants} 人 · 媒体加密',
                      accent,
                    ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '服务器内的房间',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _loading ? null : _refresh,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  if (!_loading && _rooms.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: Text(
                          '这里还没有房间\n创建一个，或稍后下拉刷新',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  for (final room in _rooms)
                    Card(
                      margin: const EdgeInsets.only(top: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: accent.withValues(alpha: .14),
                          child: Icon(Icons.public, color: accent),
                        ),
                        title: Text(
                          room.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '房主：${room.hostNickname} · ${room.memberCount}/${room.maxParticipants} 人',
                        ),
                        trailing: FilledButton.tonal(
                          onPressed:
                              room.memberCount >= room.maxParticipants ||
                                  (_activeSession != null &&
                                      _activeSession!.roomId != room.id)
                              ? null
                              : () => _joinRoom(room),
                          child: Text(
                            _activeSession?.roomId == room.id
                                ? '返回'
                                : room.memberCount >= room.maxParticipants
                                ? '已满'
                                : '加入',
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _emptyServers(Color accent) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.language_rounded, size: 72, color: accent),
          const SizedBox(height: 20),
          const Text(
            '添加你自己的对讲服务器',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text(
            'App 不预置公共服务器。地址和访问凭证只保存在这台手机。',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _editProfile,
            icon: const Icon(Icons.add),
            label: const Text('添加服务器'),
          ),
        ],
      ),
    ),
  );

  Widget _statusCard(
    IconData icon,
    String title,
    String subtitle,
    Color color,
  ) => Card(
    margin: const EdgeInsets.only(top: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ActiveInternetRoomCard extends StatelessWidget {
  const _ActiveInternetRoomCard({
    required this.session,
    required this.accent,
    required this.onResume,
  });

  final InternetRoomSession session;
  final Color accent;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) => Card(
    color: accent.withValues(alpha: .10),
    child: ListTile(
      key: const ValueKey('active-internet-room-card'),
      onTap: onResume,
      leading: CircleAvatar(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        child: const Icon(Icons.call_rounded),
      ),
      title: Text(
        session.summary.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: const Text('通话保持中 · 邀请码已保存'),
      trailing: Badge(
        isLabelVisible: session.unreadChatCount > 0,
        label: Text('${session.unreadChatCount}'),
        child: Icon(Icons.arrow_forward_rounded, color: accent),
      ),
    ),
  );
}

class _ServerProfileDialog extends StatefulWidget {
  const _ServerProfileDialog({this.existing});
  final ServerProfile? existing;
  @override
  State<_ServerProfileDialog> createState() => _ServerProfileDialogState();
}

class _ServerProfileDialogState extends State<_ServerProfileDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _url = TextEditingController(
    text: widget.existing?.baseUrl ?? '',
  );
  late final TextEditingController _token = TextEditingController(
    text: widget.existing?.accessToken ?? '',
  );
  String? _error;

  void _submit() {
    final raw = _url.text.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      setState(() => _error = '请输入不含查询参数的 HTTPS 地址');
      return;
    }
    final normalized = uri
        .replace(
          path: uri.path.endsWith('/')
              ? uri.path.substring(0, uri.path.length - 1)
              : uri.path,
        )
        .toString();
    Navigator.pop(
      context,
      ServerProfile(
        id:
            widget.existing?.id ??
            '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
        name: _name.text.trim().isEmpty ? uri.host : _name.text.trim(),
        baseUrl: normalized,
        accessToken: _token.text.trim(),
        instanceId: widget.existing?.instanceId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? '添加服务器' : '编辑服务器'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: '名称（可选）'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'HTTPS 地址',
              hintText: 'https://talk.example.com',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            obscureText: true,
            autocorrect: false,
            decoration: const InputDecoration(labelText: '服务器访问凭证（私有服务器）'),
          ),
          const SizedBox(height: 10),
          const Text(
            '凭证使用 Android 安全存储保存，不会写入日志。',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('保存并连接')),
    ],
  );
}

class _CreateOptions {
  const _CreateOptions(
    this.name,
    this.maxParticipants,
    this.hostTimeoutMinutes,
    this.allowAdminListening,
  );
  final String name;
  final int maxParticipants;
  final int hostTimeoutMinutes;
  final bool allowAdminListening;
}

class _CreateRoomDialog extends StatefulWidget {
  const _CreateRoomDialog({
    required this.initialName,
    required this.serverMaximum,
    required this.adminListeningSupported,
  });
  final String initialName;
  final int serverMaximum;
  final bool adminListeningSupported;
  @override
  State<_CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<_CreateRoomDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  late final _maximum = TextEditingController(
    text: min(25, widget.serverMaximum).toString(),
  );
  final _timeout = TextEditingController(text: '10');
  String? _error;
  bool _allowAdminListening = false;

  void _submit() {
    final maximum = int.tryParse(_maximum.text.trim());
    final timeout = int.tryParse(_timeout.text.trim());
    if (_name.text.trim().isEmpty ||
        maximum == null ||
        maximum < 2 ||
        maximum > widget.serverMaximum ||
        timeout == null ||
        timeout < 1 ||
        timeout > 60) {
      setState(
        () => _error = '房间名不能为空；人数为 2–${widget.serverMaximum}，断线时长为 1–60 分钟',
      );
      return;
    }
    Navigator.pop(
      context,
      _CreateOptions(_name.text.trim(), maximum, timeout, _allowAdminListening),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('创建网络房间'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            maxLength: 80,
            decoration: const InputDecoration(labelText: '房间名'),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _maximum,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '人数上限'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _timeout,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '房主断线/分钟'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '房主断线期间保留身份，超时后由在线成员接任。全房无人在线仍在 10 分钟后回收。',
            style: TextStyle(fontSize: 12),
          ),
          if (widget.adminListeningSupported) ...[
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _allowAdminListening,
              onChanged: (value) =>
                  setState(() => _allowAdminListening = value),
              title: const Text('允许服务器管理员实时收听'),
              subtitle: const Text('开启后，房间密钥会加密托管在自部署服务器；监听期间所有成员都会看到提示。'),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('创建')),
    ],
  );
}
