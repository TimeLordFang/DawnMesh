import 'package:flutter/material.dart';

import '../../core/courier/courier_store.dart';
import '../../core/session/room_session.dart';
import '../../l10n/app_strings.dart';

class CourierPage extends StatefulWidget {
  const CourierPage({super.key, this.session});
  final RoomSession? session;
  @override
  State<CourierPage> createState() => _CourierPageState();
}

class _CourierPageState extends State<CourierPage> {
  late Future<CourierStore> _loading = CourierStore.open();
  final _text = TextEditingController();
  final _decrypted = <String, Future<String>>{};
  String? _recipient;
  bool _busy = false;
  String tr(String zh, String en) => AppStrings.of(context).isEn ? en : zh;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                '操作未完成。请检查是否已开启转交、联系人和存储容量，再重试。',
                'Could not complete this action. Check that forwarding is enabled, the contact is saved, and storage has space.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('离线转交', 'Offline forwarding'))),
    body: FutureBuilder<CourierStore>(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(() => _loading = CourierStore.open()),
              child: Text(
                tr('安全存储暂不可用，点按重试', 'Secure storage unavailable. Tap to retry'),
              ),
            ),
          );
        }
        final store = snapshot.data;
        if (store == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListenableBuilder(
          listenable: store,
          builder: (context, _) => _body(store),
        );
      },
    ),
  );

  Widget _body(CourierStore store) {
    final contacts = store.contacts;
    if (!contacts.any((c) => c.identity.id == _recipient)) _recipient = null;
    final items = store.items.reversed.toList();
    final currentDigests = items.map((i) => i.envelope.digest).toSet();
    _decrypted.removeWhere((key, _) => !currentDigests.contains(key));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          tr(
            '将短消息密封给指定的人，由同样开启转交的房间成员携带。离开房间或重启后保留，最长 24 小时；需要再次遇到收件人或其他转交者，不保证送达。',
            'Seal a short message for one person and let opted-in room members carry it. It survives leaving and restarting for up to 24 hours. Delivery requires later encounters and is not guaranteed.',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          tr(
            '默认关闭，不会录存通话或普通聊天。转交者看不到正文，但能看到通信双方的安全身份和到期时间。每机最多 64 条、256 KiB；每条本机最多发送 8 次、最多经过 4 次转交。',
            'Off by default. Calls and room chat are never collected. Carriers cannot read content, but can see routing identities and expiry. Per device: 64 items / 256 KiB; 8 sends per item and up to 4 hops.',
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('接收并转交密封消息', 'Receive and carry sealed messages')),
          subtitle: Text(
            tr(
              '开启后在已认证的房间内交换；关闭后保留本机数据但停止交换。',
              'Exchange inside authenticated rooms. Turning off keeps local data and stops exchange.',
            ),
          ),
          value: store.enabled,
          onChanged: _busy
              ? null
              : (value) => _act(() => store.setEnabled(value)),
        ),
        if (store.error != null)
          Text(
            tr(
              '本轮转交已暂停，已保存的数据仍在。',
              'Forwarding paused; saved data is retained.',
            ),
          ),
        if (widget.session?.secureCodec?.authentication case final auth?)
          ExpansionTile(
            title: Text(tr('记住房内联系人', 'Save room contacts')),
            children: [
              for (final member in widget.session!.members)
                if (member.memberId != widget.session!.selfMemberId &&
                    auth.members[member.memberId] != null)
                  ListTile(
                    title: Text(member.nickname),
                    subtitle: SelectableText(
                      auth.members[member.memberId]!.identity.fingerprint,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.person_add_alt_1),
                      tooltip: tr(
                        '已核对安全号码，记住此人',
                        'Save after comparing safety numbers',
                      ),
                      onPressed: _busy
                          ? null
                          : () => _act(
                              () => store.rememberContact(
                                member.nickname,
                                auth.members[member.memberId]!.identity,
                              ),
                            ),
                    ),
                  ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(AppStrings.of(context).safetyNumberHint),
              ),
            ],
          ),
        if (contacts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              tr(
                '先进入房间核对安全号码，再记住联系人。以后可在这里给离线的对方留言。',
                'Save a contact after comparing safety numbers in a room, then leave them a message here while they are offline.',
              ),
            ),
          ),
        if (contacts.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            initialValue: _recipient,
            key: ValueKey(_recipient),
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('收件人', 'Recipient')),
            items: [
              for (final contact in contacts)
                DropdownMenuItem(
                  value: contact.identity.id,
                  child: Text(contact.name),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _recipient = value),
          ),
          TextField(
            controller: _text,
            minLines: 2,
            maxLines: 5,
            maxLength: 320,
            decoration: InputDecoration(
              labelText: tr(
                '密封留言（最多 1024 字节）',
                'Sealed message (up to 1024 bytes)',
              ),
            ),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.outbox_outlined),
            label: Text(tr('加入转交队列', 'Queue for forwarding')),
            onPressed: _busy || !store.enabled || _recipient == null
                ? null
                : () => _act(() async {
                    await store.compose(_recipient!, _text.text);
                    _text.clear();
                  }),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          tr('本机保存 ${items.length}/64 条', '${items.length}/64 items stored'),
        ),
        for (final item in items) _item(store, item),
        const SizedBox(height: 16),
        Text(
          tr(
            '撤回会传播签名撤回通知；不能抹去对方已读的内容或不遵守撤回的副本。清空仅删除本机数据并关闭转交。',
            'Recall sends an authenticated cancellation. It cannot erase already-read content or copies held by non-cooperating devices. Clear removes local data and disables forwarding.',
          ),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(
                        tr('清空并关闭转交？', 'Clear and disable forwarding?'),
                      ),
                      content: Text(
                        tr(
                          '删除本机留言和联系人，其他设备的副本不会因此删除。',
                          'Delete local messages and contacts. Copies on other devices remain.',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(tr('取消', 'Cancel')),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(tr('清空', 'Clear')),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) await _act(store.clear);
                },
          child: Text(tr('清空并关闭', 'Clear and disable')),
        ),
      ],
    );
  }

  Widget _item(CourierStore store, CourierItem item) {
    final envelope = item.envelope;
    final mine = envelope.author.id == store.identity.public.id;
    final received = envelope.recipient.id == store.identity.public.id;
    final peer = mine ? envelope.recipient : envelope.author;
    final contact = store.contacts
        .where((c) => c.identity.fingerprint == peer.fingerprint)
        .firstOrNull;
    final title = contact?.name ?? tr('未记住的联系人', 'Unsaved contact');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${mine
                  ? tr('发给', 'To')
                  : received
                  ? tr('来自', 'From')
                  : tr('托管', 'Carrying')} $title',
            ),
            if (contact == null)
              SelectableText(
                peer.fingerprint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (envelope.revoked)
              Text(tr('已撤回 · 等待通知其他副本', 'Recalled · notifying other copies'))
            else if (mine)
              Text(item.localText ?? tr('已密封', 'Sealed'))
            else if (received)
              FutureBuilder<String>(
                future: _decrypted.putIfAbsent(
                  envelope.digest,
                  () => envelope.decrypt(store.identity),
                ),
                builder: (context, snapshot) => Text(
                  snapshot.hasError
                      ? tr('消息无法解密', 'Could not decrypt')
                      : snapshot.data ?? '…',
                ),
              )
            else
              Text(tr('正文只有收件人可读', 'Only the recipient can read this content')),
            Text(
              tr(
                '到期：${DateTime.fromMillisecondsSinceEpoch(envelope.expiresMs).toLocal()}',
                'Expires: ${DateTime.fromMillisecondsSinceEpoch(envelope.expiresMs).toLocal()}',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (mine && !envelope.revoked) ...[
              Text(
                tr(
                  '已排队，不代表对方已收到',
                  'Queued; recipient delivery is not confirmed',
                ),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _act(() => store.revoke(envelope.key)),
                child: Text(tr('撤回', 'Recall')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
