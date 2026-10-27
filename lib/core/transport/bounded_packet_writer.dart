import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

/// One bounded, ordered application queue per link. Only authenticated audio
/// may expire; congestion first evicts audio, then fails a saturated control link.
class BoundedPacketWriter {
  BoundedPacketWriter({
    required this.write,
    required this.onFailure,
    this.writeText,
    this.capacity = 128,
    this.maxRealtimeAge = const Duration(milliseconds: 200),
    this.writeTimeout = const Duration(seconds: 5),
    DateTime Function()? now,
  }) : assert(capacity > 0),
       now = now ?? DateTime.now;

  final Future<void> Function(Uint8List) write;
  final Future<void> Function(String)? writeText;
  final void Function(Object) onFailure;
  final int capacity;
  final Duration maxRealtimeAge;
  final Duration writeTimeout;
  final DateTime Function() now;
  final _queue = Queue<_Packet>();
  Future<void>? _draining;
  bool _closed = false;
  int droppedAudio = 0;
  int writtenBytes = 0;
  int highWatermark = 0;
  int get pending => _queue.length;

  bool send(Uint8List bytes, {bool realtime = false}) {
    return _enqueue(_Packet(Uint8List.fromList(bytes), realtime, now()));
  }

  /// WebSocket authentication messages share the queue with binary frames.
  /// Calling add() directly during addStream() is illegal on a Dart socket.
  bool sendText(String text) {
    if (writeText == null) throw StateError('Text writes are not configured');
    return _enqueue(_Packet(text, false, now()));
  }

  bool _enqueue(_Packet packet) {
    if (_closed) return false;
    _queue.removeWhere((p) {
      final expired =
          p.realtime && now().difference(p.queuedAt) > maxRealtimeAge;
      if (expired) droppedAudio++;
      return expired;
    });
    if (_queue.length >= capacity) {
      final audio = _queue.where((p) => p.realtime).firstOrNull;
      if (audio != null) {
        _queue.remove(audio);
        droppedAudio++;
      } else if (packet.realtime) {
        droppedAudio++;
        return true;
      } else {
        _fail(StateError('Reliable packet queue full'));
        return false;
      }
    }
    _queue.add(packet);
    if (_queue.length > highWatermark) highWatermark = _queue.length;
    _draining ??= Future<void>.microtask(_drain);
    return true;
  }

  Future<void> _drain() async {
    try {
      while (!_closed && _queue.isNotEmpty) {
        final packet = _queue.removeFirst();
        if (packet.realtime &&
            now().difference(packet.queuedAt) > maxRealtimeAge) {
          droppedAudio++;
          continue;
        }
        final data = packet.data;
        if (data is Uint8List) {
          await write(data).timeout(writeTimeout);
          writtenBytes += data.length;
        } else {
          await writeText!(data as String).timeout(writeTimeout);
        }
      }
    } catch (error) {
      _fail(error);
    } finally {
      _draining = null;
    }
  }

  Future<void> flush() async {
    while (_draining != null) {
      await _draining;
    }
  }

  void _fail(Object error) {
    if (_closed) return;
    close();
    onFailure(error);
  }

  void close() {
    _closed = true;
    _queue.clear();
  }
}

class _Packet {
  _Packet(this.data, this.realtime, this.queuedAt);
  final Object data;
  final bool realtime;
  final DateTime queuedAt;
}
