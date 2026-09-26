import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dawn_mesh/core/security/room_invite.dart';
import 'package:dawn_mesh/ui/widgets/room_invite_dialog.dart';

void main() {
  testWidgets(
    'create generates four digits, accepts custom leading zeros and legacy six digits',
    (tester) async {
      RoomInvite? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  chosen = await requestRoomInvite(context, creating: true);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      for (final code in ['0012', '001234']) {
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        final input = find.byKey(const ValueKey('room-invite-input'));
        expect(
          tester.widget<TextField>(input).controller!.text,
          matches(r'^\d{4}$'),
        );
        await tester.tap(find.text('随机生成'));
        await tester.pump();
        expect(
          tester.widget<TextField>(input).controller!.text,
          matches(r'^\d{4}$'),
        );
        await tester.enterText(input, '12345');
        await tester.tap(find.text('创建房间'));
        await tester.pump();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.enterText(input, code);
        await tester.tap(find.text('创建房间'));
        await tester.pumpAndSettle();
        expect(chosen?.code, code);
      }
    },
  );
}
