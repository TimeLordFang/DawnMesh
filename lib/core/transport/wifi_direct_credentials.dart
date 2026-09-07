import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../security/room_invite.dart';

/// Stable Wi-Fi Direct credentials derived from the room invite.
///
/// Android 10+ can join a known P2P group with its SSID and passphrase. This
/// avoids the legacy WPS-style approval prompt on the group owner's phone.
class WifiDirectCredentials {
  final String networkName;
  final String passphrase;

  const WifiDirectCredentials({
    required this.networkName,
    required this.passphrase,
  });

  factory WifiDirectCredentials.fromInvite(RoomInvite invite) {
    final digest = sha256.convert(
      utf8.encode('DawnMesh-WiFi-Direct-v1:${invite.code}'),
    );
    final hex =
        digest.bytes
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join();
    return WifiDirectCredentials(
      networkName:
          'DIRECT-${hex.substring(0, 2)}-DawnMesh-${hex.substring(2, 10)}',
      passphrase: 'DM${hex.substring(10, 32)}',
    );
  }

  Map<String, String> toMap() => {
    'networkName': networkName,
    'passphrase': passphrase,
  };
}
