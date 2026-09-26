import 'package:dawn_mesh/core/internet/presence_announcements.dart';
import 'package:dawn_mesh/core/internet/internet_models.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

InternetMember member(String id, {bool online = true}) => InternetMember(
  id: id,
  nickname: id,
  isHost: false,
  canSpeak: true,
  isOnline: online,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('initial roster is silent, persistent disconnect announces once, flaps are quiet', () {
    fakeAsync((time) {
      final spoken = <String>[];
      final notice = PresenceAnnouncements(
        selfId: 'me',
        speak: (kind, name) async => spoken.add('$kind:$name'),
      )..enabled = true;
      notice.observe([
        member('me'),
        member('one'),
        member('old', online: false),
      ]);
      time.elapse(const Duration(seconds: 3));
      expect(spoken, isEmpty);
      notice.observe([member('me'), member('one', online: false)]);
      time.elapse(const Duration(seconds: 1));
      notice.observe([member('me'), member('one')]);
      time.elapse(const Duration(seconds: 3));
      expect(spoken, isEmpty);
      notice.observe([member('me'), member('one', online: false)]);
      time.elapse(const Duration(seconds: 3));
      notice.observe([member('me'), member('one', online: false)]);
      time.elapse(const Duration(seconds: 3));
      expect(spoken, ['offline:one']);
      notice.dispose();
    });
  });
  test('explicit exit replaces pending disconnect and duplicate events are ignored', () {
    fakeAsync((time) {
      final spoken = <String>[];
      final notice = PresenceAnnouncements(
        selfId: 'me',
        speak: (kind, name) async => spoken.add('$kind:$name'),
      )..enabled = true;
      notice.observe([member('one')]);
      notice.observe([member('one', online: false)]);
      notice.memberLeft('one', 'one', 'event1');
      notice.memberLeft('one', 'one', 'event1');
      notice.memberLeft('me', 'me', 'event2');
      notice.observe([]);
      time.elapse(const Duration(seconds: 3));
      expect(spoken, ['left:one']);
      notice.dispose();
    });
  });
  test('off, recovery and dispose cancel pending notices and never replay old departures', () {
    fakeAsync((time) {
      final spoken = <String>[];
      final notice = PresenceAnnouncements(
        selfId: 'me',
        speak: (kind, name) async => spoken.add(kind),
      )..enabled = true;
      notice.observe([member('one')]);
      notice.observe([member('one', online: false)]);
      notice.enabled = false;
      time.elapse(const Duration(seconds: 3));
      notice.enabled = true;
      notice.suspend();
      notice.memberLeft('one', 'one', 'lost-event');
      notice.observe([member('one', online: false)]);
      time.elapse(const Duration(seconds: 3));
      notice.observe([member('one')]);
      notice.observe([member('one', online: false)]);
      notice.dispose();
      time.elapse(const Duration(seconds: 3));
      expect(spoken, isEmpty);
    });
  });
}
