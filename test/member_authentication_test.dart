import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'dart:typed_data';

import 'package:dawn_mesh/core/protocol/frame.dart';
import 'package:dawn_mesh/core/protocol/frame_type.dart';
import 'package:dawn_mesh/core/security/member_identity.dart';
import 'package:dawn_mesh/core/security/room_admission.dart';
import 'package:dawn_mesh/core/security/session_crypto.dart';
import 'package:dawn_mesh/core/security/session_handshake.dart';
import 'package:flutter_test/flutter_test.dart';

class _Peer {
  final token = Uint8List(16);
  final sent = <Frame>[];
  late RoomAdmission admission;
  late SecureFrameCodec codec;
  bool ready = false;
  static Future<_Peer> create(int id) async {
    final peer = _Peer();
    peer.token[0] = id;
    peer.admission = RoomAdmission(
      passwordScalar: BigInt.one,
      token: peer.token,
      identity: await MemberIdentity.create(),
      send: peer.sent.add,
      onReady: (codec) async {
        peer.codec = codec;
        peer.ready = true;
      },
    );
    addTearDown(peer.admission.close);
    return peer;
  }

  Future<void> join(_Peer host, int id) async {
    admission.startClient(freshAttempt: true);
    await host.admission.handle(sent.last);
    await admission.handle(host.sent.last);
    await host.admission.handle(sent.last);
    await admission.handle(host.sent.last);
    expect(host.codec.authentication!.bind(id, token), true);
  }
}

Frame _message(int sender, {int seq = 1}) => Frame(
  type: FrameType.chat,
  senderId: sender,
  seq: seq,
  payload: Uint8List.fromList([10, 20]),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('secure storage retains independent identity across restarts and concurrent loads', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final identities = await Future.wait(
      List.generate(4, (_) => MemberIdentity.load()),
    );
    expect(identities.map((i) => i.public.id).toSet(), hasLength(1));
    final bytes = [1, 2, 3];
    expect(
      await identities.last.public.verify(
        bytes,
        await identities.first.sign(bytes),
      ),
      true,
    );
    final restarted = await MemberIdentity.load();
    expect(restarted.public.id, identities.first.public.id);
  });

  test(
    'PAKE pins host, certified members cannot impersonate each other',
    () async {
      final host = await _Peer.create(1), guest = await _Peer.create(2);
      await host.admission.startHost();
      await guest.join(host, 2);
      final membership = Frame(
        type: FrameType.memberKeys,
        senderId: 1,
        seq: 1,
        payload: host.codec.authentication!.encodeMembers(),
      );
      guest.codec.authentication!.acceptMembers(
        (await guest.codec.open(await host.codec.seal(membership))).payload,
      );
      expect(
        (await host.codec.open(await guest.codec.seal(_message(2)))).senderId,
        2,
      );
      await expectLater(
        host.codec.open(await guest.codec.seal(_message(1))),
        throwsStateError,
      );
      // Possession of the group cipher is insufficient to populate the replay
      // window with an invalid member signature.
      final forged = await guest.codec.seal(_message(1, seq: 2));
      await expectLater(host.codec.open(forged), throwsStateError);
      final payload = forged.payload;
      final aad = Uint8List.fromList([
        FrameType.sealed.value,
        1,
        0,
        2,
        1,
        ...payload.take(5),
      ]);
      expect(
        await host.codec.cipher.decrypt(
          EncryptedPacket(
            nonce: Uint8List.sublistView(payload, 6, 18),
            ciphertext: Uint8List.sublistView(payload, 18),
          ),
          associatedData: aad,
        ),
        isNotEmpty,
      );
      final original = guest.codec;
      await guest.join(host, 2);
      expect(
        identical(original, guest.codec),
        true,
        reason: 'Reconnect preserves replay windows',
      );
    },
  );

  test('leave rotates epoch only for remaining keys, lost grant retries, old epoch rejected', () async {
    final host = await _Peer.create(1),
        a = await _Peer.create(2),
        b = await _Peer.create(3);
    await host.admission.startHost();
    await a.join(host, 2);
    await b.join(host, 3);
    final roster = host.codec.authentication!.encodeMembers();
    a.codec.authentication!.acceptMembers(roster);
    b.codec.authentication!.acceptMembers(roster);
    final old = await a.codec.seal(_message(2));
    await host.admission.revoke({2});
    expect(host.codec.epoch, 2);
    final grant = host.sent.last;
    expect(grant.payload.sublist(2, 18), b.token);
    await a.admission.handle(grant);
    expect(a.codec.epoch, 1);
    host.sent.clear();
    host.admission.retryKeyGrants();
    expect(host.sent.length, 1);
    await b.admission.handle(host.sent.single);
    expect(b.codec.epoch, 2);
    await expectLater(host.codec.open(old), throwsStateError);
    final newMessage = await host.codec.seal(_message(1, seq: 2));
    expect((await b.codec.open(newMessage)).senderId, 1);
    await expectLater(a.codec.open(newMessage), throwsStateError);
    host.admission.acknowledgeEpoch(3);
    host.sent.clear();
    host.admission.retryKeyGrants();
    expect(host.sent, isEmpty);
  });

  test('rekey invalidates cached PAKE grants from the prior epoch', () async {
    final host = await _Peer.create(1), guest = await _Peer.create(2);
    await host.admission.startHost();
    await guest.join(host, 2);
    final confirmation = guest.sent.last;
    await host.admission.revoke({2});
    host.sent.clear();
    await host.admission.handle(confirmation);
    expect(host.sent, isEmpty);
  });

  test(
    'certified successor rekeys survivors and admits them after host transfer',
    () async {
      final host = await _Peer.create(1),
          a = await _Peer.create(2),
          b = await _Peer.create(3);
      await host.admission.startHost();
      await a.join(host, 2);
      await b.join(host, 3);
      final roster = host.codec.authentication!.encodeMembers();
      for (final peer in [a, b]) {
        peer.codec.authentication!.acceptMembers(roster);
        peer.codec.authentication!.transfer({2: 1, 3: 2});
      }
      await a.admission.promote();
      await b.admission.handle(a.sent.last);
      expect(b.codec.epoch, 2);
      expect((await b.codec.open(await a.codec.seal(_message(1)))).senderId, 1);
      await b.join(a, 2);
      expect((await a.codec.open(await b.codec.seal(_message(2)))).senderId, 2);
      await expectLater(
        host.codec.open(await b.codec.seal(_message(2, seq: 3))),
        throwsStateError,
      );
    },
  );

  test('host identity cannot claim a guest slot; restarted guest keeps its member ID', () async {
    final host = await _Peer.create(1), guest = await _Peer.create(2);
    await host.admission.startHost();
    await guest.join(host, 2);
    final auth = host.codec.authentication!;
    expect(() => auth.register(Uint8List(16), auth.host), throwsStateError);
    final freshToken = Uint8List(16)..[0] = 99;
    auth.register(freshToken, guest.codec.authentication!.self.public);
    expect(auth.existingMemberId(freshToken), 2);
    expect(auth.bind(3, freshToken), false);
    auth.register(freshToken, guest.codec.authentication!.self.public);
    expect(auth.bind(2, freshToken), true);
    expect(auth.members[2]!.token, freshToken);
  });

  test('host also proves ownership of the key bundle pinned by PAKE', () async {
    final original = await _Peer.create(7),
        fake = await _Peer.create(1),
        guest = await _Peer.create(2);
    fake.admission.identity!.public.signing.setAll(
      0,
      original.admission.identity!.public.signing,
    );
    await fake.admission.startHost();
    guest.admission.startClient(freshAttempt: true);
    await fake.admission.handle(guest.sent.last);
    await guest.admission.handle(fake.sent.last);
    await fake.admission.handle(guest.sent.last);
    await guest.admission.handle(fake.sent.last);
    expect(
      guest.ready,
      false,
      reason: 'a public-key clone cannot issue a trusted host grant',
    );
  });

  test(
    'PAKE requires signing-key possession and binds the agreement key too',
    () async {
      final host = await _Peer.create(1),
          victim = await _Peer.create(2),
          attacker = await _Peer.create(3);
      await host.admission.startHost();
      await victim.join(host, 2);
      final auth = host.codec.authentication!;
      final genuine = victim.admission.identity!.public;
      final forgedBundle = MemberPublicIdentity(
        Uint8List.fromList(genuine.signing),
        attacker.admission.identity!.public.agreement,
      );
      expect(
        () => auth.register(attacker.token, forgedBundle),
        throwsStateError,
      );
      // A peer can advertise any public bytes; it must prove ownership of the
      // claimed signing key over this PAKE transcript and the complete key bundle.
      attacker.admission.identity!.public.signing.setAll(0, genuine.signing);
      attacker.admission.startClient(freshAttempt: true);
      await host.admission.handle(attacker.sent.last);
      await attacker.admission.handle(host.sent.last);
      final before = host.sent.length;
      await host.admission.handle(attacker.sent.last);
      expect(
        host.sent,
        hasLength(before),
        reason: 'no traffic key grant for a cloned public key',
      );
      expect(auth.members[2]!.identity.bytes, genuine.bytes);
      expect(auth.bind(3, attacker.token), false);
    },
  );

  test(
    'a stolen admission token cannot replace an already bound member key',
    () async {
      final host = await _Peer.create(1),
          a = await _Peer.create(2),
          attacker = await _Peer.create(2);
      await host.admission.startHost();
      await a.join(host, 2);
      attacker.admission.startClient(freshAttempt: true);
      await host.admission.handle(attacker.sent.last);
      await attacker.admission.handle(host.sent.last);
      await expectLater(
        host.admission.handle(attacker.sent.last),
        throwsStateError,
      );
    },
  );
}
