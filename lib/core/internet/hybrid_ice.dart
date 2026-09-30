import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

/// Only private host addresses may cross the encrypted direct-audio channel.
bool isPrivateHostCandidate(String candidate) {
  final parts = candidate.trim().split(RegExp(r'\s+'));
  if (parts.length < 8 ||
      !(parts[0].startsWith('candidate:') ||
          parts[0].startsWith('a=candidate:')) ||
      parts[6] != 'typ' ||
      parts[7] != 'host') {
    return false;
  }
  final ip = parts[4].toLowerCase();
  final octets = ip.split('.').map(int.tryParse).toList();
  return (octets.length == 4 &&
          octets.every((n) => n != null && n >= 0 && n <= 255) &&
          (octets[0] == 10 ||
              (octets[0] == 192 && octets[1] == 168) ||
              (octets[0] == 172 && octets[1]! >= 16 && octets[1]! <= 31))) ||
      ((ip.startsWith('fc') || ip.startsWith('fd') || ip.startsWith('fe80:')) &&
          ip.contains(':'));
}

/// Reliable signaling can still finish decrypting out of order. Hold trickled
/// candidates until the matching remote SDP is installed, with bounded storage.
class HybridIceInbox {
  final Map<String, _IceSession> _sessions = {};
  static String _key(String from, String session) => '$from\u0000$session';

  Future<void> receive(
    String from,
    String session,
    Map<String, dynamic> data,
  ) async {
    final candidate = data['candidate'];
    final mid = data['sdpMid'];
    final index = data['sdpMLineIndex'];
    if (session.isEmpty ||
        session.length > 64 ||
        candidate is! String ||
        candidate.length > 2048 ||
        !isPrivateHostCandidate(candidate) ||
        (mid != null && (mid is! String || mid.length > 64)) ||
        (index != null && (index is! int || index < 0 || index > 16))) {
      return;
    }
    final key = _key(from, session);
    if (!_sessions.containsKey(key) && _sessions.length >= 8) return;
    final entry = _sessions.putIfAbsent(key, _IceSession.new);
    final fingerprint = '$mid|$index|$candidate';
    if (entry.seen.length >= 64 || !entry.seen.add(fingerprint)) return;
    final value = rtc.RTCIceCandidate(candidate, mid as String?, index as int?);
    final add = entry.add;
    if (add == null) {
      entry.pending.add(value);
    } else {
      await add(value);
    }
  }

  Future<void> activate(
    String from,
    String session,
    Future<void> Function(rtc.RTCIceCandidate) add,
  ) async {
    final key = _key(from, session);
    _sessions.removeWhere((k, _) => k.startsWith('$from\u0000') && k != key);
    if (!_sessions.containsKey(key) && _sessions.length >= 8) {
      final pending = _sessions.keys
          .where((k) => _sessions[k]!.add == null)
          .firstOrNull;
      if (pending != null) _sessions.remove(pending);
    }
    final entry = _sessions.putIfAbsent(key, _IceSession.new)..add = add;
    final pending = entry.pending.toList();
    entry.pending.clear();
    for (final candidate in pending) {
      await add(candidate);
    }
  }

  void forget(String from) =>
      _sessions.removeWhere((key, _) => key.startsWith('$from\u0000'));
  void clear() => _sessions.clear();
}

class _IceSession {
  final pending = <rtc.RTCIceCandidate>[];
  final seen = <String>{};
  Future<void> Function(rtc.RTCIceCandidate)? add;
}
