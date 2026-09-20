import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/platform/chat_media_service.dart';
import '../../l10n/app_strings.dart';

class ChatImageBubble extends StatefulWidget {
  const ChatImageBubble({
    super.key,
    required this.bytes,
    required this.name,
    required this.isMine,
  });

  final Uint8List bytes;
  final String name;
  final bool isMine;

  @override
  State<ChatImageBubble> createState() => _ChatImageBubbleState();
}

class _ChatImageBubbleState extends State<ChatImageBubble> {
  final _media = ChatMediaService();
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _media.saveImage(widget.bytes, widget.name);
      if (mounted) {
        final s = AppStrings.of(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.chatImageSaved)));
      }
    } catch (_) {
      if (mounted) {
        final s = AppStrings.of(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.chatImageSaveFailed)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _preview() {
    final s = AppStrings.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: .7,
                maxScale: 5,
                child: Center(
                  child: Image.memory(widget.bytes, fit: BoxFit.contain),
                ),
              ),
            ),
            SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: s.chatCloseSheet,
                    color: Colors.white,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  IconButton(
                    tooltip: s.chatSaveImage,
                    color: Colors.white,
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.download_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Stack(
      children: [
        InkWell(
          key: const ValueKey('chat-image-preview'),
          onTap: _preview,
          borderRadius: BorderRadius.circular(12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              widget.bytes,
              width: 220,
              height: 164,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(
                width: 220,
                height: 120,
                child: Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
        ),
        Positioned(
          right: 5,
          bottom: 5,
          child: Material(
            color: Colors.black.withValues(alpha: .58),
            shape: const CircleBorder(),
            child: IconButton(
              key: const ValueKey('save-chat-image'),
              tooltip: s.chatSaveImage,
              visualDensity: VisualDensity.compact,
              color: Colors.white,
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_rounded, size: 20),
            ),
          ),
        ),
      ],
    );
  }
}
