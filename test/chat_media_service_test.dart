import 'dart:typed_data';

import 'package:dawn_mesh/core/platform/chat_media_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detects supported chat image formats by file signature', () {
    expect(
      ChatMediaService.detectMimeType(Uint8List.fromList([0xff, 0xd8, 0xff])),
      'image/jpeg',
    );
    expect(
      ChatMediaService.detectMimeType(
        Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]),
      ),
      'image/png',
    );
    expect(
      ChatMediaService.detectMimeType(
        Uint8List.fromList([
          0x52,
          0x49,
          0x46,
          0x46,
          0,
          0,
          0,
          0,
          0x57,
          0x45,
          0x42,
          0x50,
        ]),
      ),
      'image/webp',
    );
  });

  test('rejects unknown or truncated image data', () {
    expect(ChatMediaService.detectMimeType(Uint8List(0)), isNull);
    expect(
      ChatMediaService.detectMimeType(Uint8List.fromList([0x89, 0x50])),
      isNull,
    );
    expect(
      ChatMediaService.detectMimeType(
        Uint8List.fromList(List<int>.filled(12, 0)),
      ),
      isNull,
    );
  });
}
