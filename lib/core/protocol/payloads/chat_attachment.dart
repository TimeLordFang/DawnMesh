import 'dart:convert';
import 'dart:typed_data';

enum ChatAttachmentFormat {
  jpeg(1, 'image/jpeg'),
  png(2, 'image/png'),
  webp(3, 'image/webp'),
  opus(4, 'audio/opus');

  const ChatAttachmentFormat(this.value, this.mimeType);
  final int value;
  final String mimeType;
  bool get isImage => this != opus;

  static ChatAttachmentFormat? fromValue(int value) {
    for (final format in values) {
      if (format.value == value) return format;
    }
    return null;
  }

  static ChatAttachmentFormat? fromMimeType(String mimeType) {
    for (final format in values) {
      if (format.mimeType == mimeType) return format;
    }
    return null;
  }
}

/// A bounded room attachment chunk; images and explicit Opus notes share framing.
///
/// The fixed header is 23 bytes, followed by a UTF-8 file name and up to 384
/// image bytes. This stays below the secure frame plaintext ceiling.
class ChatAttachmentChunkPayload {
  const ChatAttachmentChunkPayload({
    required this.transferId,
    required this.timestampMs,
    required this.senderCode,
    required this.chunkIndex,
    required this.chunkCount,
    required this.format,
    required this.name,
    required this.data,
  });

  static const int version = 1;
  static const int fixedHeaderBytes = 23;
  static const int maxNameBytes = 32;
  static const int maxChunkBytes = 384;
  static const int maxImageBytes = 192 * 1024;
  static const int maxChunkCount = (maxImageBytes + 255) ~/ 256;

  final int transferId;
  final int timestampMs;
  final String senderCode;
  final int chunkIndex;
  final int chunkCount;
  final ChatAttachmentFormat format;
  final String name;
  final Uint8List data;

  Uint8List encode() {
    final nameBytes = utf8.encode(name);
    if (nameBytes.isEmpty || nameBytes.length > maxNameBytes) {
      throw ArgumentError('invalid image name');
    }
    if (chunkCount <= 0 ||
        chunkCount > maxChunkCount ||
        chunkIndex < 0 ||
        chunkIndex >= chunkCount ||
        data.isEmpty ||
        data.length > maxChunkBytes) {
      throw ArgumentError('invalid image chunk');
    }
    final result = Uint8List(fixedHeaderBytes + nameBytes.length + data.length);
    final view = ByteData.sublistView(result);
    result[0] = version;
    view.setUint32(1, transferId, Endian.big);
    view.setUint64(5, timestampMs, Endian.big);
    final code = ascii.encode(senderCode.padRight(4).substring(0, 4));
    result.setRange(13, 17, code);
    view.setUint16(17, chunkIndex, Endian.big);
    view.setUint16(19, chunkCount, Endian.big);
    result[21] = format.value;
    result[22] = nameBytes.length;
    result.setRange(
      fixedHeaderBytes,
      fixedHeaderBytes + nameBytes.length,
      nameBytes,
    );
    result.setRange(fixedHeaderBytes + nameBytes.length, result.length, data);
    return result;
  }

  static ChatAttachmentChunkPayload? decode(Uint8List bytes) {
    if (bytes.length <= fixedHeaderBytes || bytes[0] != version) return null;
    final view = ByteData.sublistView(bytes);
    final chunkIndex = view.getUint16(17, Endian.big);
    final chunkCount = view.getUint16(19, Endian.big);
    final format = ChatAttachmentFormat.fromValue(bytes[21]);
    final nameLength = bytes[22];
    if (format == null ||
        nameLength == 0 ||
        nameLength > maxNameBytes ||
        chunkCount == 0 ||
        chunkCount > maxChunkCount ||
        chunkIndex >= chunkCount ||
        bytes.length <= fixedHeaderBytes + nameLength ||
        bytes.length > fixedHeaderBytes + nameLength + maxChunkBytes) {
      return null;
    }
    try {
      final name = utf8.decode(
        bytes.sublist(fixedHeaderBytes, fixedHeaderBytes + nameLength),
        allowMalformed: false,
      );
      final data = Uint8List.fromList(
        bytes.sublist(fixedHeaderBytes + nameLength),
      );
      return ChatAttachmentChunkPayload(
        transferId: view.getUint32(1, Endian.big),
        timestampMs: view.getUint64(5, Endian.big),
        senderCode: ascii.decode(bytes.sublist(13, 17)).trim(),
        chunkIndex: chunkIndex,
        chunkCount: chunkCount,
        format: format,
        name: name,
        data: data,
      );
    } catch (_) {
      return null;
    }
  }
}
