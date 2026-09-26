import 'dart:async';

import 'package:flutter/services.dart';

import '../diagnostics/app_log.dart';
import 'internet_models.dart';

/// Debounces presence transitions without replaying the initial/recovery roster.
class PresenceAnnouncements {
  PresenceAnnouncements({
    required this.selfId,
    Future<void> Function(String kind, String name)? speak,
  }) : _speak = speak ?? _platformSpeak;
  final String selfId;
  final Future<void> Function(String, String) _speak;
  static const _channel = MethodChannel('dev.dawnmesh.intercom/presence_audio');
  final Map<String, bool> _online = {};
  final Map<String, Timer> _pending = {};
  final Set<String> _leftEvents = {};
  bool _ready = false;
  bool _enabled = false;
  bool _disposed = false;
  bool _usedAudio = false;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) _cancelAudio();
  }

  void observe(List<InternetMember> members) {
    if (_disposed) return;
    final current = {for (final member in members) member.id: member.isOnline};
    for (final member in members) {
      if (member.id == selfId) continue;
      if (member.isOnline) {
        _pending.remove(member.id)?.cancel();
      } else if (_ready && _online[member.id] == true && _enabled) {
        _queue(
          member.id,
          'offline',
          member.nickname,
          const Duration(seconds: 2),
        );
      }
    }
    // Removed identities are announced only by an explicit member_left event.
    for (final id in _online.keys) {
      if (!current.containsKey(id)) _pending.remove(id)?.cancel();
    }
    _online
      ..clear()
      ..addAll(current);
    _ready = true;
  }

  void memberLeft(String id, String name, String eventId) {
    if (_disposed ||
        !_ready ||
        !_enabled ||
        id == selfId ||
        eventId.isEmpty ||
        !_leftEvents.add(eventId)) {
      return;
    }
    if (_leftEvents.length > 256) _leftEvents.remove(_leftEvents.first);
    _pending.remove(id)?.cancel();
    // Explicit exits replace any pending disconnect prompt and are not inferred
    // from roster removal (which can also mean expiry or initial synchronization).
    _emit('left', name);
  }

  void _queue(String id, String kind, String name, Duration delay) {
    _pending.remove(id)?.cancel();
    _pending[id] = Timer(delay, () {
      _pending.remove(id);
      if (!_disposed && _enabled && _ready && _online[id] == false) {
        _emit(kind, name);
      }
    });
  }

  void _emit(String kind, String name) {
    _usedAudio = true;
    unawaited(
      _speak(kind, name).catchError((Object error) {
        AppLog.warn('DawnPresence', '无法播放成员语音提示', error);
      }),
    );
  }

  static Future<void> _platformSpeak(String kind, String name) =>
      _channel.invokeMethod<void>('announce', {'kind': kind, 'name': name});

  void _cancelAudio() {
    for (final timer in _pending.values) {
      timer.cancel();
    }
    _pending.clear();
    if (_usedAudio) {
      _usedAudio = false;
      unawaited(_channel.invokeMethod<void>('stop').catchError((Object _) {}));
    }
  }

  void suspend() {
    _ready = false;
    _online.clear();
    _cancelAudio();
  }

  void dispose() {
    _disposed = true;
    suspend();
  }
}
