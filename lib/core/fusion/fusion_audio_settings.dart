import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../diagnostics/app_log.dart';
import '../internet/internet_audio_profile.dart';

/// The same Opus quality policy as public rooms, applied to native capture.
class FusionAudioSettings extends ChangeNotifier {
  FusionAudioSettings({
    required this.applyBitrate,
    this.changed,
    Future<List<ConnectivityResult>> Function()? readNetwork,
    Stream<List<ConnectivityResult>>? networkChanges,
  }) : _readNetwork = readNetwork ?? Connectivity().checkConnectivity,
       _networkChanges = networkChanges ?? Connectivity().onConnectivityChanged;

  final Future<void> Function(int) applyBitrate;
  final VoidCallback? changed;
  final Future<List<ConnectivityResult>> Function() _readNetwork;
  final Stream<List<ConnectivityResult>> _networkChanges;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Future<void>? _startTask;
  Future<void> _applyQueue = Future.value();
  bool _closed = false, _manual = false;
  int _networkRevision = 0;
  bool _metered = true;
  InternetAudioProfile _profile = InternetAudioProfile.dataSaver;

  bool get metered => _metered;
  InternetAudioProfile get profile => _profile;
  int get bitrate => _profile.bitrateFor(metered: _metered);

  Future<void> start() => _startTask ??= _start();
  Future<void> _start() async {
    if (_closed) return;
    final revision = _networkRevision;
    _subscription = _networkChanges.listen((results) {
      _networkRevision++;
      unawaited(_networkChanged(results));
    }, onError: (Object _) {});
    try {
      final results = await _readNetwork();
      if (!_closed && revision == _networkRevision) {
        await _networkChanged(results);
      }
    } catch (_) {
      // Unknown bearer stays conservative; offline local voice still works.
    }
  }

  Future<void> _networkChanged(List<ConnectivityResult> results) async {
    if (_closed) return;
    final metered =
        !results.contains(ConnectivityResult.wifi) &&
        !results.contains(ConnectivityResult.ethernet);
    final profile = _manual
        ? _profile
        : InternetAudioProfileDetails.recommended(metered: metered);
    if (_metered == metered && _profile == profile) return;
    _metered = metered;
    _profile = profile;
    await _apply();
  }

  Future<void> select(InternetAudioProfile profile) async {
    if (_closed) return;
    _manual = true;
    if (_profile == profile) return;
    _profile = profile;
    await _apply();
  }

  Future<void> _apply() {
    notifyListeners();
    changed?.call();
    // Serialize native writes, reading the latest choice when each write runs.
    // Changing quality must never restart capture or alter the PTT gate.
    _applyQueue = _applyQueue
        .then((_) async {
          if (!_closed) await applyBitrate(bitrate);
        })
        .catchError((Object error) {
          AppLog.warn('Fusion', '调整音质码率失败：$error');
        });
    return _applyQueue;
  }

  @override
  void dispose() {
    _closed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
