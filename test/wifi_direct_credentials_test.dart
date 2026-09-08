import 'package:flutter_test/flutter_test.dart';
import 'package:dawn_mesh/core/security/room_invite.dart';
import 'package:dawn_mesh/core/transport/wifi_direct_credentials.dart';

void main() {
  test('same invite derives valid stable Wi-Fi Direct credentials', () {
    final first = WifiDirectCredentials.fromInvite(RoomInvite.parse('012345'));
    final second = WifiDirectCredentials.fromInvite(RoomInvite.parse('012345'));
    expect(first.toMap(), second.toMap());
    expect(
      first.networkName,
      matches(RegExp(r'^DIRECT-[0-9a-f]{2}-DawnMesh-[0-9a-f]{8}$')),
    );
    expect(first.passphrase, matches(RegExp(r'^DM[0-9a-f]{22}$')));
  });

  test('different invites do not share transport credentials', () {
    final first = WifiDirectCredentials.fromInvite(RoomInvite.parse('012345'));
    final second = WifiDirectCredentials.fromInvite(RoomInvite.parse('012346'));
    expect(first.networkName, isNot(second.networkName));
    expect(first.passphrase, isNot(second.passphrase));
    expect(first.passphrase, isNot(contains('012345')));
  });
}
