import 'dart:typed_data';

import 'frame.dart';
import 'frame_type.dart';
import 'room_limits.dart';

/// Large control messages keep the existing 512-byte wire frame and AEAD limit.
/// Only roster/transfer/fusion messages may be assembled; never audio or PAKE.
class ControlFragments {
  static const headerBytes = 9;
  static const maxParts = 16;
  static const lifetime = Duration(seconds: 12);
  final _pending = <(int, int), _Assembly>{};

  static bool supports(FrameType type) =>
      type == FrameType.roster ||
      type == FrameType.hostHandover ||
      type == FrameType.hostAnnounce ||
      type == FrameType.fusionState;

  static FrameType? originalType(Frame frame) =>
      frame.type == FrameType.controlFragment && frame.payload.isNotEmpty
      ? FrameType.fromValue(frame.payload[0])
      : null;

  static Iterable<Frame> split({
    required FrameType type,
    required int senderId,
    required int messageId,
    required Uint8List payload,
    required int maxPayload,
    required int Function() nextSeq,
  }) sync* {
    if (maxPayload <= headerBytes || maxPayload > Frame.maxPayloadSize) {
      throw ArgumentError('Invalid wire payload limit');
    }
    if (payload.length > RoomLimits.maxControlMessageBytes) {
      throw ArgumentError('Control message exceeds limit');
    }
    if (payload.length <= maxPayload) {
      yield Frame(
        type: type,
        senderId: senderId,
        seq: nextSeq(),
        payload: payload,
      );
      return;
    }
    if (!supports(type)) {
      throw ArgumentError('Unsupported fragmented control message');
    }
    final chunkSize = maxPayload - headerBytes;
    final count = (payload.length + chunkSize - 1) ~/ chunkSize;
    if (count > maxParts) throw ArgumentError('Too many fragments');
    for (var index = 0; index < count; index++) {
      final start = index * chunkSize;
      final end = (start + chunkSize).clamp(0, payload.length);
      final part = Uint8List(headerBytes + end - start);
      final header = ByteData.sublistView(part)
        ..setUint8(0, type.value)
        ..setUint32(1, messageId)
        ..setUint8(5, index)
        ..setUint8(6, count)
        ..setUint16(7, payload.length);
      part.setRange(headerBytes, part.length, payload, start);
      yield Frame(
        type: FrameType.controlFragment,
        senderId: senderId,
        seq: nextSeq(),
        payload: header.buffer.asUint8List(),
      );
    }
  }

  Frame? accept(Frame frame, DateTime now) {
    _pending.removeWhere(
      (_, value) => now.difference(value.created) >= lifetime,
    );
    final type = originalType(frame);
    if (type == null ||
        !supports(type) ||
        frame.payload.length <= headerBytes ||
        frame.senderId < 1 ||
        frame.senderId > RoomLimits.wifiMembers) {
      return null;
    }
    final header = ByteData.sublistView(frame.payload);
    final key = (frame.senderId, header.getUint32(1));
    final index = header.getUint8(5),
        count = header.getUint8(6),
        length = header.getUint16(7);
    if (count < 2 ||
        count > maxParts ||
        index >= count ||
        length <= 0 ||
        length > RoomLimits.maxControlMessageBytes) {
      return null;
    }
    var assembly = _pending[key];
    if (assembly == null) {
      // Two concurrent messages per sender; bound uncompleted allocations.
      if (_pending.length >= RoomLimits.wifiMembers * 2 ||
          _pending.keys.where((entry) => entry.$1 == frame.senderId).length >=
              2) {
        return null;
      }
      assembly = _Assembly(type, count, length, now);
      _pending[key] = assembly;
    }
    if (assembly.type != type ||
        assembly.parts.length != count ||
        assembly.length != length) {
      _pending.remove(key);
      return null;
    }
    final body = Uint8List.sublistView(frame.payload, headerBytes);
    final existing = assembly.parts[index];
    if (existing != null) {
      if (!_equal(existing, body)) _pending.remove(key);
      return null;
    }
    if (assembly.receivedBytes + body.length > length) {
      _pending.remove(key);
      return null;
    }
    assembly.parts[index] = Uint8List.fromList(body);
    assembly.receivedBytes += body.length;
    if (assembly.parts.any((part) => part == null)) return null;
    _pending.remove(key);
    if (assembly.receivedBytes != length) return null;
    return Frame.reassembled(
      type: type,
      senderId: frame.senderId,
      seq: frame.seq,
      payload: Uint8List.fromList(
        assembly.parts.expand((part) => part!).toList(),
      ),
    );
  }

  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void clear() => _pending.clear();
}

class _Assembly {
  _Assembly(this.type, int count, this.length, this.created)
    : parts = List<Uint8List?>.filled(count, null);
  final FrameType type;
  final int length;
  final DateTime created;
  final List<Uint8List?> parts;
  int receivedBytes = 0;
}
