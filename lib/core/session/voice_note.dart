import 'dart:typed_data';

/// Explicitly retained 16 kHz mono, 20 ms Opus packets. This container is private
/// to DawnMesh; it is not labelled as an Ogg/Opus file. Nothing is written to disk.
class VoiceNote {
  static const maxPackets =
      750; // 15 seconds, irrespective of wall-clock jumps.
  static const maxBytes = 96 * 1024;
  VoiceNote(List<Uint8List> packets)
    : packets = List.unmodifiable(packets.map(Uint8List.fromList));
  final List<Uint8List> packets;
  Duration get duration => Duration(milliseconds: packets.length * 20);

  Uint8List encode() {
    if (packets.isEmpty || packets.length > maxPackets) {
      throw ArgumentError('Voice note duration');
    }
    final result = BytesBuilder()
      ..add([1, packets.length >> 8, packets.length & 255]);
    for (final packet in packets) {
      if (packet.isEmpty || packet.length > 512) {
        throw ArgumentError('Voice packet size');
      }
      result.add([packet.length >> 8, packet.length & 255]);
      result.add(packet);
    }
    final bytes = result.takeBytes();
    if (bytes.length > maxBytes) throw ArgumentError('Voice note byte budget');
    return bytes;
  }

  static VoiceNote? decode(Uint8List bytes) {
    if (bytes.length < 3 || bytes.length > maxBytes || bytes[0] != 1) {
      return null;
    }
    final count = (bytes[1] << 8) | bytes[2];
    if (count < 1 || count > maxPackets) return null;
    final packets = <Uint8List>[];
    var offset = 3;
    for (var i = 0; i < count; i++) {
      if (offset + 2 > bytes.length) return null;
      final size = (bytes[offset] << 8) | bytes[offset + 1];
      offset += 2;
      if (size < 1 || size > 512 || offset + size > bytes.length) return null;
      packets.add(Uint8List.sublistView(bytes, offset, offset + size));
      offset += size;
    }
    return offset == bytes.length ? VoiceNote(packets) : null;
  }
}

/// Mutable only while the local user explicitly retains a PTT segment.
class VoiceNoteCapture {
  VoiceNoteCapture(
    this.transferId,
    this.timestampMs,
    this.senderCode, {
    this.namespace = '',
  });
  final String namespace;
  final int transferId, timestampMs;
  final String senderCode;
  final packets = <Uint8List>[];
  int _bytes = 3;
  String get messageId =>
      '${senderCode}_$namespace${timestampMs}_voice_$transferId';
  bool add(Uint8List packet) {
    if (packet.isEmpty ||
        packet.length > 512 ||
        packets.length >= VoiceNote.maxPackets ||
        _bytes + packet.length + 2 > VoiceNote.maxBytes) {
      return false;
    }
    packets.add(Uint8List.fromList(packet));
    _bytes += packet.length + 2;
    return true;
  }

  VoiceNote finish() => VoiceNote(packets);
}
