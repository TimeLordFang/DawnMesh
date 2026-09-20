import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';

class PickedChatImage {
  const PickedChatImage({
    required this.bytes,
    required this.mimeType,
    required this.name,
  });

  final Uint8List bytes;
  final String mimeType;
  final String name;
}

/// Selects, downsizes and saves chat images without keeping permanent file
/// paths. Chat history is intentionally memory-only, just like text history.
class ChatMediaService {
  ChatMediaService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  static const int maxImageBytes = 192 * 1024;
  final ImagePicker _picker;

  Future<PickedChatImage?> pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 960,
      maxHeight: 960,
      imageQuality: 70,
      requestFullMetadata: false,
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) throw const FormatException('图片内容为空');
    if (bytes.length > maxImageBytes) {
      throw const FormatException('压缩后的图片仍超过 192 KB，请选择更小的图片');
    }
    final mimeType = detectMimeType(bytes);
    if (mimeType == null) {
      throw const FormatException('仅支持 JPEG、PNG 和 WebP 图片');
    }
    final extension = switch (mimeType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    return PickedChatImage(
      bytes: bytes,
      mimeType: mimeType,
      name: 'DawnMesh_${DateTime.now().millisecondsSinceEpoch}.$extension',
    );
  }

  Future<void> saveImage(Uint8List bytes, String name) async {
    final baseName = name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    await Gal.putImageBytes(bytes, name: baseName, album: 'DawnMesh');
  }

  static String? detectMimeType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return null;
  }
}
