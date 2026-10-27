import 'package:flutter/material.dart';

import '../../core/session/room_session.dart';
import '../../l10n/app_strings.dart';

/// Numbers identify public keys, not mutable nicknames or short device codes.
class MemberSafetySheet extends StatelessWidget {
  const MemberSafetySheet({super.key, required this.session});
  final RoomSession session;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .7,
      child: StreamBuilder(
        stream: session.membersStream,
        builder: (context, _) {
          final s = AppStrings.of(context);
          final identities = session.secureCodec?.authentication?.members;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                s.memberSafetyNumbers,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(s.safetyNumberHint),
              for (final member in session.members)
                if (identities?[member.memberId] case final identity?) ...[
                  const SizedBox(height: 20),
                  Text(
                    member.nickname,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    identity.identity.fingerprint,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ],
            ],
          );
        },
      ),
    ),
  );
}
