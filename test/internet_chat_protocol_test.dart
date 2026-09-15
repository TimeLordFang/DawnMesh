import 'dart:convert';
import 'dart:typed_data';

import 'package:dawn_mesh/core/security/session_crypto.dart';
import 'package:dawn_mesh/core/security/spake2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decrypts the DawnMesh browser chat protocol vector', () async {
    final roomKey = Uint8List.fromList(
      List<int>.generate(32, (index) => index),
    );
    final cipher = await SessionCipher.fromKey(
      Spake2Keys.hkdf(roomKey, 'DawnMesh internet chat v1'),
    );
    final packet = Spake2.hexBytes(
      '000102030405060708090a0b'
      'f3607290423845140aa7a23b191e5f8d4f7f0adde7df856b3cabc2e5de9eb2f'
      'e596f91fa502918abf4340b8b5ae3bef74386b45213a36d677df8365ff95b790'
      '64d34a5c1ad60dd9b4e3e6b5e5a5d16c44b7ef1fb12c98cc6ad8d01e525f41'
      'ef4',
    );
    final clear = await cipher.decrypt(
      EncryptedPacket(
        nonce: Uint8List.sublistView(packet, 0, 12),
        ciphertext: Uint8List.sublistView(packet, 12),
      ),
      associatedData: Uint8List.fromList(
        utf8.encode('dawnmesh.chat.v1\u0000member-test'),
      ),
    );

    expect(
      utf8.decode(clear),
      '{"id":"1","senderId":"member-test","senderName":"Web",'
      '"text":"hello","sentAt":1}',
    );
  });
}
