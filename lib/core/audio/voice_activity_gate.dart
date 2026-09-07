import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

/// Local level-based voice activation: 100 ms pre-roll, 400 ms hangover.
/// Sound above the adaptive noise floor opens it; no speech is sent to a server.
class VoiceActivityGate {
  final _preRoll = ListQueue<Uint8List>();
  int _openUntil = -1;
  double _noise = 0.002;
  bool isOpen = false;

  List<Uint8List> process(Uint8List packet, double level, int nowMs) {
    if (!level.isFinite) level = 0;
    final threshold = max(0.008, min(0.04, _noise * 3));
    final triggered = level >= threshold;
    if (triggered) _openUntil = nowMs + 400;
    if (triggered || nowMs < _openUntil) {
      isOpen = true;
      final result = [..._preRoll, packet];
      _preRoll.clear();
      return result;
    }
    isOpen = false;
    _noise = _noise * 0.97 + level.clamp(0, 0.015) * 0.03;
    _preRoll.add(Uint8List.fromList(packet));
    while (_preRoll.length > 5) {
      _preRoll.removeFirst();
    }
    return const [];
  }

  void reset() {
    _preRoll.clear();
    _openUntil = -1;
    _noise = 0.002;
    isOpen = false;
  }
}
