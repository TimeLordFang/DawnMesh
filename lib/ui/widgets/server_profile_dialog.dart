import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/internet/internet_models.dart';
import 'dialog_action_button.dart';

class ServerProfileDialog extends StatefulWidget {
  const ServerProfileDialog({super.key, this.existing});
  final ServerProfile? existing;
  @override
  State<ServerProfileDialog> createState() => _ServerProfileDialogState();
}

class _ServerProfileDialogState extends State<ServerProfileDialog> {
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

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

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
            '凭证仅保存在这台设备的安全存储中，不会写入日志。',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
    actions: [
      DialogActionButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      DialogActionButton.primary(onPressed: _submit, child: const Text('保存')),
    ],
  );
}
