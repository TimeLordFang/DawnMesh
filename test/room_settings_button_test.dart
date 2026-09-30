import 'dart:async';

import 'package:dawn_mesh/ui/widgets/room_settings_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'room settings scroll at large text sizes and close with the room',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ended = StreamController<Object?>.broadcast();
      addTearDown(ended.close);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            appBar: AppBar(
              title: const Text('房间'),
              actions: [
                RoomSettingsButton(
                  dismissEvents: ended.stream,
                  items: (_) => [
                    for (var i = 0; i < 8; i++)
                      ListTile(
                        title: Text('设置 $i'),
                        subtitle: const Text('房间设置说明'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('room-settings-button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('设置 7'), 180);
      expect(find.text('设置 7').hitTestable(), findsOneWidget);
      ended.add(null);
      await tester.pumpAndSettle();
      expect(find.text('设置 7'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
