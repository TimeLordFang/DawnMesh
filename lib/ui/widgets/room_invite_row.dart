import 'dart:async';
import 'package:flutter/material.dart';

class HostRoomInviteRow extends StatelessWidget {
  const HostRoomInviteRow({
    super.key,
    required this.isHost,
    required this.code,
  });

  final bool isHost;
  final String? code;

  @override
  Widget build(BuildContext context) {
    final value = code;
    if (!isHost || value == null) return const SizedBox.shrink();
    return RoomInviteRow(code: value);
  }
}

/// A short-lived reveal; hidden digits are absent from the accessibility tree.
class RoomInviteRow extends StatefulWidget {
  const RoomInviteRow({
    super.key,
    required this.code,
    this.initiallyVisible = true,
  });

  final String code;
  final bool initiallyVisible;

  @override
  State<RoomInviteRow> createState() => _RoomInviteRowState();
}

class _RoomInviteRowState extends State<RoomInviteRow>
    with WidgetsBindingObserver {
  Timer? _timer;
  late bool _visible;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _visible = widget.initiallyVisible;
    _scheduleHide();
  }

  @override
  void didUpdateWidget(RoomInviteRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code) {
      _visible = widget.initiallyVisible;
      _scheduleHide();
    }
  }

  void _scheduleHide() {
    _timer?.cancel();
    if (_visible) {
      _timer = Timer(const Duration(seconds: 10), () {
        if (mounted) setState(() => _visible = false);
      });
    }
  }

  void _toggle() {
    setState(() => _visible = !_visible);
    _scheduleHide();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _visible) {
      _timer?.cancel();
      setState(() => _visible = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '邀请码',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            _visible ? widget.code : '••••••',
            semanticsLabel:
                _visible ? '邀请码 ${widget.code.split('').join(' ')}' : '邀请码已隐藏',
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: 3,
            ),
          ),
        ),
        IconButton(
          tooltip: _visible ? '隐藏邀请码' : '显示邀请码，10 秒后隐藏',
          onPressed: _toggle,
          iconSize: 20,
          icon: Icon(
            _visible
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: Colors.white70,
          ),
        ),
      ],
    ),
  );
}
