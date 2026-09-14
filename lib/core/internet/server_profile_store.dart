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

  Future<String> deviceId() async {
    final existing = await _storage.read(key: _deviceKey);
    if (existing != null && existing.length >= 24) return existing;
    final random = Random.secure();
    final generated = base64UrlEncode(
      List<int>.generate(24, (_) => random.nextInt(256)),
    );
    await _storage.write(key: _deviceKey, value: generated);
    return generated;
  }
}
