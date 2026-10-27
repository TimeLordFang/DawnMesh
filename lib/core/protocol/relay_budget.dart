import 'dart:typed_data';

import 'frame.dart';
import 'frame_type.dart';

/// Mutable transport metadata, outside the signed message and AEAD AAD.
/// Honest gateways decrease it on every relay hop, including cloud bridges.
/// It is a loop/traffic bound, not an authorization credential. Altering it
/// cannot change or impersonate the authenticated inner message.
abstract final class RelayBudget {
  static const maximum = 8;
  static int? remaining(Frame frame) {
    if (frame.payload.isEmpty || frame.payload[0] != 3) return null;
    if (frame.type == FrameType.sealed) {
      return frame.payload.length >= 6 ? frame.payload[5] : null;
    }
    if (frame.type == FrameType.handshakeHello ||
        frame.type == FrameType.handshakeConfirm) {
      return frame.seq >> 8;
    }
    return null;
  }

  static Frame? forward(Frame frame) {
    final budget = remaining(frame);
    if (budget == null || budget < 1 || budget > maximum) return null;
    final payload = Uint8List.fromList(frame.payload);
    var seq = frame.seq;
    if (frame.type == FrameType.sealed) {
      payload[5] = budget - 1;
    } else {
      seq = ((budget - 1) << 8) | (seq & 255);
    }
    return Frame(
      type: frame.type,
      senderId: frame.senderId,
      seq: seq,
      payload: payload,
    );
  }

  /// Different path lengths still identify the very same encrypted packet.
  static Uint8List cacheKeyBytes(List<int> bytes) {
    final normalized = Uint8List.fromList(bytes);
    if (bytes.length >= 12 &&
        bytes[0] == FrameType.sealed.value &&
        bytes[6] == 3) {
      normalized[11] = 0;
    } else if (bytes.length >= 7 &&
        bytes[6] == 3 &&
        (bytes[0] == FrameType.handshakeHello.value ||
            bytes[0] == FrameType.handshakeConfirm.value)) {
      normalized[2] = 0;
    }
    return normalized;
  }
}
