import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dawn_mesh/ui/widgets/ptt_button.dart';

void main() {
  testWidgets(
    'accessible activation toggles sustained speech and background releases it',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var pressed = false;
      final changes = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return PttButton(
                isNight: false,
                isPressed: pressed,
                onStateChanged: (value) {
                  changes.add(value);
                  setState(() => pressed = value);
                },
              );
            },
          ),
        ),
      );
      void activate() {
        final node = tester.getSemantics(find.byType(PttButton));
        node.owner!.performAction(node.id, SemanticsAction.tap);
      }

      activate();
      await tester.pump();
      expect(pressed, isTrue);
      await tester.pump(const Duration(seconds: 2));
      expect(pressed, isTrue);
      activate();
      await tester.pump();
      expect(pressed, isFalse);
      activate();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(pressed, isFalse);
      expect(changes, [true, false, true, false]);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      semantics.dispose();
    },
  );
  testWidgets('removing a latched PTT releases it', (tester) async {
    final changes = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: PttButton(
          isNight: false,
          isPressed: true,
          onStateChanged: changes.add,
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(changes, [false]);
  });
}
