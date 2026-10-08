import 'dart:convert';
import 'dart:typed_data';

/// Byte bounds preserve complete Unicode code points in all room payloads.
Uint8List boundedUtf8(String text, int maxBytes) {
  final result = <int>[];
  for (final rune in text.runes) {
    final bytes = utf8.encode(String.fromCharCode(rune));
    if (result.length + bytes.length > maxBytes) break;
    result.addAll(bytes);
  }
  return Uint8List.fromList(result);
}
