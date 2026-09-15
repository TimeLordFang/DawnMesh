import 'package:flutter/material.dart';

import '../../core/session/device_code.dart';
import '../../core/session/member.dart';
import '../theme/app_theme.dart';
import 'avatar_frame.dart';

List<Member> stableMemberDisplayOrder(Iterable<Member> members) {
  final result = members.toList();
  result.sort((a, b) {
    final (aName, aCode) = DeviceCode.split(a.nickname);
    final (bName, bCode) = DeviceCode.split(b.nickname);
    // 新版成员都有稳定的设备短码。用它排序可避免房主交接后成员号重编
    // 导致头像跳位；旧版无短码时再按昵称和成员号确定性兜底。
    final byCode = (aCode ?? '').compareTo(bCode ?? '');
    if (byCode != 0) return byCode;
    final byName = aName.compareTo(bName);
    if (byName != 0) return byName;
    return a.memberId.compareTo(b.memberId);
  });
  return result;
}

/// Member Horizontal Orbit Track displaying active participants and speaking waves.
class MemberOrbit extends StatelessWidget {
  final List<Member> members;
  final bool isNight;

  const MemberOrbit({super.key, required this.members, required this.isNight});

  @override
  Widget build(BuildContext context) {
    final orderedMembers = stableMemberDisplayOrder(members);
    final allNicknames = orderedMembers.map((m) => m.nickname).toList();

    return SizedBox(
      // 头像 64 + 昵称一行 + 冲突短码一行，留点余量。
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        itemCount: orderedMembers.length,
        separatorBuilder: (_, _) => const SizedBox(width: 18),
        itemBuilder: (context, index) {
          final member = orderedMembers[index];
          final (baseName, _) = DeviceCode.split(member.nickname);
          final hasConflict = DeviceCode.hasConflict(baseName, allNicknames);
          return _MemberAvatarChip(
            member: member,
            isNight: isNight,
            hasConflict: hasConflict,
          );
        },
      ),
    );
  }
}

class _MemberAvatarChip extends StatelessWidget {
  final Member member;
  final bool isNight;
  final bool hasConflict;

  const _MemberAvatarChip({
    required this.member,
    required this.isNight,
    this.hasConflict = false,
  });

  @override
  Widget build(BuildContext context) {
    // 昵称里带的 3 位数字短码按需展示：只有在同名冲突时才展示，避免平时多余干扰。
    final (displayName, code) = DeviceCode.split(member.nickname);

    return SizedBox(
      // 固定宽度，昵称才有可省略的边界；否则横向列表里 Row 拿到的是无界约束。
      width: 92,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AvatarFrame(
            senderCode: code ?? '${member.memberId}',
            nickname: displayName,
            isHost: member.isHost,
            isSpeaking: member.isSpeaking,
            isMuted: member.isMuted,
            size: 64,
            isNight: isNight,
          ),
          const SizedBox(height: 6),
          Text(
            displayName,
            style: TextStyle(
              fontSize: 14,
              color: isNight
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (code != null && hasConflict)
            Text(
              '${DeviceCode.separator}$code',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.4,
                fontFeatures: const [FontFeature.tabularFigures()],
                color:
                    (isNight
                            ? AppTheme.darkTextSecondary
                            : AppTheme.lightTextSecondary)
                        .withValues(alpha: 0.7),
              ),
            ),
        ],
      ),
    );
  }
}
