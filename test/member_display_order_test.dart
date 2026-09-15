import 'package:dawn_mesh/core/internet/internet_models.dart';
import 'package:dawn_mesh/core/session/member.dart';
import 'package:dawn_mesh/ui/widgets/member_orbit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'near-field avatar order survives host transfer member-id remapping',
    () {
      final before = stableMemberDisplayOrder([
        Member(memberId: 1, nickname: '原房主 #731', isHost: true),
        Member(memberId: 2, nickname: '新房主 #204'),
        Member(memberId: 3, nickname: '成员 #518'),
      ]).map((member) => member.nickname).toList();

      final after = stableMemberDisplayOrder([
        Member(memberId: 2, nickname: '原房主 #731'),
        Member(memberId: 1, nickname: '新房主 #204', isHost: true),
        Member(memberId: 3, nickname: '成员 #518'),
      ]).map((member) => member.nickname).toList();

      expect(after, before);
    },
  );

  test('internet avatar order ignores host and speaking state changes', () {
    final before = <InternetMember>[
      const InternetMember(
        id: 'old-host',
        nickname: '原房主',
        isHost: true,
        canSpeak: true,
        sortOrder: 0,
      ),
      const InternetMember(
        id: 'new-host',
        nickname: '新房主',
        isHost: false,
        canSpeak: true,
        sortOrder: 1,
      ),
    ]..sort(InternetMember.compareStable);
    final after = <InternetMember>[
      const InternetMember(
        id: 'new-host',
        nickname: '新房主',
        isHost: true,
        canSpeak: true,
        sortOrder: 1,
        isSpeaking: true,
      ),
      const InternetMember(
        id: 'old-host',
        nickname: '原房主',
        isHost: false,
        canSpeak: true,
        sortOrder: 0,
      ),
    ]..sort(InternetMember.compareStable);

    expect(after.map((member) => member.id), before.map((member) => member.id));
  });
}
