import 'dart:typed_data';

import 'package:dawn_mesh/core/internet/internet_invite_credentials.dart';
import 'package:dawn_mesh/core/security/room_invite.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const salt = 'AAECAwQFBgcICQoLDA0ODw==';
  const packet =
      'AAECAwQFBgcICQoLBuxi2D+luelGNFq4Rvwi40Fl2l8Yoc0GkL1gTKUys5DFJ4DKUI5Pe7jqLKyACMq8';
  test('matches independent scrypt and browser AES-GCM vectors', () async {
    final keys = await InternetInviteCredentials.derive(
      RoomInvite.parse('0012'),
      salt,
    );
    expect(keys.credential, 'dpGI1xd+eY4DMeu2MRF1VivNsVsVwhXMJQxoyrs0aCw=');
    final roomKey = Uint8List.fromList(List.generate(32, (i) => i));
    expect(await keys.unwrap(packet), roomKey);
    expect(await keys.unwrap(await keys.wrap(roomKey)), roomKey);
    final wrong = await InternetInviteCredentials.derive(
      RoomInvite.parse('0013'),
      salt,
    );
    expect(wrong.credential, isNot(keys.credential));
    await expectLater(wrong.unwrap(packet), throwsA(anything));
    final otherRoom = await InternetInviteCredentials.derive(
      RoomInvite.parse('0012'),
      'AAAAAAAAAAAAAAAAAAAAAA==',
    );
    expect(otherRoom.credential, isNot(keys.credential));
    await expectLater(otherRoom.unwrap(packet), throwsA(anything));
  });
}
