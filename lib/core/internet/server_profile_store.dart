import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'internet_models.dart';

class ServerProfileStore {
  ServerProfileStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _profilesKey = 'internet_server_profiles_v1';
  static const _selectedKey = 'internet_server_selected_v1';
  static const _deviceKey = 'internet_device_id_v1';
  final FlutterSecureStorage _storage;

  Future<List<ServerProfile>> loadProfiles() async {
    final raw = await _storage.read(key: _profilesKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((item) => ServerProfile.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveProfiles(List<ServerProfile> profiles) => _storage.write(
    key: _profilesKey,
    value: jsonEncode(profiles.map((profile) => profile.toJson()).toList()),
  );

  Future<String?> loadSelectedId() => _storage.read(key: _selectedKey);
  Future<void> saveSelectedId(String id) =>
      _storage.write(key: _selectedKey, value: id);

  // Serialize across store instances so two simultaneous entry points cannot
  // generate different installation identities before secure storage commits.
  static Future<void> _identityQueue = Future<void>.value();
  static Future<String> _identityOperation(Future<String> Function() load) {
    final result = _identityQueue.then((_) => load());
    _identityQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<String> deviceId() => _identityOperation(_loadDeviceId);

  Future<String> _loadDeviceId() async {
    final existing = await _storage.read(key: _deviceKey);
    if (existing != null && existing.length >= 24) return existing;
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final generated =
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    await _storage.write(key: _deviceKey, value: generated);
    return generated;
  }

  Future<String> deviceProof() => _identityOperation(_loadDeviceProof);
  Future<String> _loadDeviceProof() async {
    const key = 'installation_device_proof_v1';
    final existing = await _storage.read(key: key);
    if (existing != null && existing.length == 44) return existing;
    final random = Random.secure();
    final proof = base64Encode(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    await _storage.write(key: key, value: proof);
    return proof;
  }
}
