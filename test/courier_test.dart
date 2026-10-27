import 'dart:convert';
import 'dart:typed_data';

import 'package:dawn_mesh/core/courier/courier_envelope.dart';
import 'package:dawn_mesh/core/courier/courier_link.dart';
import 'package:dawn_mesh/core/courier/courier_store.dart';
import 'package:dawn_mesh/core/protocol/frame.dart';
import 'package:dawn_mesh/core/protocol/frame_type.dart';
import 'package:dawn_mesh/core/security/member_identity.dart';
import 'package:flutter_test/flutter_test.dart';

class _Disk {
  String? data;
  bool fail = false;
  Future<void> save(String value) async {
    if (fail) throw StateError('disk unavailable');
    data = value;
  }
}

void main() {
  var now = DateTime.utc(2026, 10, 27);
  Future<CourierStore> store(MemberIdentity identity, _Disk disk) async {
    final result = CourierStore(
      identity: identity,
      read: () async => disk.data,
      write: disk.save,
      now: () => now,
    );
    await result.load();
    return result;
  }

  setUp(() {
    now = DateTime.utc(2026, 10, 27);
  });

  test('only recipient decrypts; signature, routing and expiry tampering are rejected', () async {
    final a = await MemberIdentity.create(),
        b = await MemberIdentity.create(),
        c = await MemberIdentity.create();
    final message = await CourierEnvelope.create(
      author: a,
      recipient: b.public,
      text: '见面说 hello',
      now: now,
    );
    expect(await message.decrypt(b), '见面说 hello');
    await expectLater(message.decrypt(c), throwsStateError);
    expect(await CourierEnvelope.verify(message.wire, now), isNotNull);
    for (final position in [
      1,
      2,
      18,
      26,
      34,
      98,
      162,
      194,
      message.wire.length - 1,
    ]) {
      final bytes = Uint8List.fromList(message.wire)..[position] ^= 1;
      expect(await CourierEnvelope.verify(bytes, now), isNull);
    }
    expect(
      await CourierEnvelope.verify(
        message.wire,
        now.add(const Duration(hours: 24)),
      ),
      isNull,
    );
    await expectLater(message.revoke(c), throwsStateError);
    final revoked = await message.revoke(a);
    expect((await CourierEnvelope.verify(revoked.wire, now))!.revoked, true);
    expect(revoked.key, message.key);
  });

  test(
    'opt-in, restart budgets and persistence failures are fail-closed',
    () async {
      final a = await MemberIdentity.create(),
          b = await MemberIdentity.create();
      final disk = _Disk();
      var sender = await store(a, disk);
      await sender.rememberContact('B', b.public);
      await expectLater(
        sender.compose(b.public.id, 'message'),
        throwsStateError,
      );
      expect(sender.items, isEmpty);
      await sender.setEnabled(true);
      await sender.compose(b.public.id, 'message');
      final digest = sender.items.single.envelope.digest;
      for (var i = 0; i < CourierStore.maxSends; i++) {
        expect(await sender.takeForSend(digest), isNotNull);
        sender = await store(a, disk);
      }
      expect(await sender.takeForSend(digest), isNull);
      expect(sender.items.single.localText, 'message');
      final saved = disk.data;
      disk.fail = true;
      await expectLater(
        sender.compose(b.public.id, 'not saved'),
        throwsStateError,
      );
      expect(sender.items, hasLength(1));
      expect(disk.data, saved);
      disk.fail = false;
      await sender.setEnabled(false);
      expect(sender.inventory, isEmpty);
      now = now.add(const Duration(days: 1));
      sender = await store(a, disk);
      expect(sender.items, isEmpty);
    },
  );

  test('carrier cannot read; cancellation arriving before or after message prevents resurrection', () async {
    final a = await MemberIdentity.create(),
        b = await MemberIdentity.create(),
        c = await MemberIdentity.create();
    final message = await CourierEnvelope.create(
      author: a,
      recipient: b.public,
      text: 'secret',
      now: now,
    );
    final revoked = await message.revoke(a);
    for (final firstIsRevoke in [true, false]) {
      final carrier = await store(c, _Disk());
      await carrier.setEnabled(true);
      expect(
        await carrier.accept(firstIsRevoke ? revoked.wire : message.wire, 4),
        true,
      );
      expect(await carrier.accept(revoked.wire, 4), !firstIsRevoke);
      expect(await carrier.accept(message.wire, 4), false);
      expect(carrier.items, hasLength(1));
      expect(carrier.items.single.envelope.revoked, true);
      expect(carrier.items.single.hops, 3);
    }
    final carrier = await store(c, _Disk());
    expect(await carrier.accept(message.wire, 4), false);
    await carrier.setEnabled(true);
    expect(await carrier.accept(message.wire, 0), false);
    expect(await carrier.accept(message.wire, 5), false);
    expect(await carrier.accept(message.wire, 4), true);
    await expectLater(
      carrier.items.single.envelope.decrypt(c),
      throwsStateError,
    );
  });

  test(
    '64-envelope quota rejects new work without evicting unrecalled messages',
    () async {
      final a = await MemberIdentity.create(),
          b = await MemberIdentity.create();
      final disk = _Disk(), sender = await store(a, _Disk());
      await sender.setEnabled(true);
      await sender.rememberContact('B', b.public);
      for (var i = 0; i < CourierStore.capacity; i++) {
        await sender.compose(b.public.id, 'message $i');
      }
      expect(sender.items, hasLength(64));
      final first = sender.items.first.envelope;
      await expectLater(
        sender.compose(b.public.id, 'overflow'),
        throwsStateError,
      );
      expect(sender.items.first.envelope.digest, first.digest);
      await sender.revoke(first.key);
      expect(sender.items.first.envelope.revoked, true);
      disk.data = jsonEncode({
        'version': 1,
        'identity': a.public.id,
        'enabled': true,
        'contacts': [],
        'items': List.filled(65, {}),
      });
      await expectLater(store(a, disk), throwsFormatException);
    },
  );

  test('paged exact reconciliation delivers across two encounters, loss and restart', () async {
    final a = await MemberIdentity.create(),
        b = await MemberIdentity.create(),
        c = await MemberIdentity.create();
    final carrierDisk = _Disk();
    final sender = await store(a, _Disk()), recipient = await store(b, _Disk());
    var carrier = await store(c, carrierDisk);
    for (final s in [sender, carrier, recipient]) {
      await s.setEnabled(true);
    }
    await sender.rememberContact('B', b.public);
    await sender.compose(b.public.id, '跨房间转交');
    Future<void> encounter(
      CourierStore first,
      CourierStore second, {
      bool loseFirstBundle = false,
    }) async {
      final queue = <(int, Frame)>[];
      var seq = 0, lost = false;
      final links = <int, CourierLink>{};
      for (final (id, s) in [(1, first), (2, second)]) {
        links[id] = CourierLink(
          store: s,
          selfId: () => id,
          members: () => {1, 2},
          now: () => now,
          send: (type, data) async {
            queue.add((
              id,
              Frame.reassembled(
                type: type,
                senderId: id,
                seq: seq++,
                payload: data,
              ),
            ));
          },
        );
      }
      for (var tick = 0; tick < 15; tick++) {
        now = now.add(const Duration(seconds: 2));
        for (final link in links.values) {
          await link.tick();
        }
        var budget = 100;
        while (queue.isNotEmpty) {
          expect(--budget, greaterThan(0));
          final (source, frame) = queue.removeAt(0);
          if (loseFirstBundle &&
              !lost &&
              frame.type == FrameType.courierBundle) {
            lost = true;
            continue;
          }
          await links[source == 1 ? 2 : 1]!.handle(frame);
        }
      }
    }

    await encounter(sender, carrier, loseFirstBundle: true);
    expect(carrier.items, hasLength(1));
    carrier = await store(c, carrierDisk);
    await encounter(carrier, recipient);
    expect(recipient.items, hasLength(1));
    expect(await recipient.items.single.envelope.decrypt(b), '跨房间转交');
    expect(
      recipient.inventory,
      isEmpty,
      reason: 'recipient stops carrying delivered content',
    );
    await sender.revoke(sender.items.single.envelope.key);
    await encounter(sender, carrier);
    await encounter(carrier, recipient);
    expect(recipient.items.single.envelope.revoked, true);
  });
}
