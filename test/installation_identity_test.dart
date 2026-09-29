import 'dart:convert';

import 'package:dawn_mesh/core/internet/server_profile_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'concurrent stores share one installation UUID and independent secret',
    () async {
      final values = await Future.wait(
        List.generate(8, (_) => ServerProfileStore().deviceId()),
      );
      expect(values.toSet().length, 1);
      expect(
        values.first,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      final proofs = await Future.wait(
        List.generate(8, (_) => ServerProfileStore().deviceProof()),
      );
      expect(proofs.toSet().length, 1);
      expect(base64Decode(proofs.first).length, 32);
      expect(proofs.first, isNot(values.first));
    },
  );
  test('upgrading preserves the previously installed identity', () async {
    const legacy = 'legacy-installation-device-identity';
    FlutterSecureStorage.setMockInitialValues({
      'internet_device_id_v1': legacy,
    });
    expect(await ServerProfileStore().deviceId(), legacy);
    expect(await ServerProfileStore().deviceProof(), isNotEmpty);
  });
}
