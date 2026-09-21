import 'package:dawn_mesh/core/internet/internet_models.dart';
import 'package:dawn_mesh/ui/widgets/server_profile_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const servers = [
    ServerProfile(id: 'a', name: '晨曦服务器', baseUrl: 'https://a.example.test'),
    ServerProfile(id: 'b', name: '远方服务器', baseUrl: 'https://b.example.test'),
  ];

  testWidgets('server choices open in a bottom sheet and selection returns', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    ServerProfile? changed;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ServerProfilePicker(
              profiles: servers,
              selected: servers.first,
              onSelected: (value) => changed = value,
              isNight: false,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('server-profile-picker')));
    await tester.pumpAndSettle();
    expect(find.text('切换服务器'), findsOneWidget);
    expect(find.byKey(const ValueKey('server-option-a')), findsOneWidget);
    final second = find.byKey(const ValueKey('server-option-b'));
    expect(second, findsOneWidget);
    expect(tester.getBottomLeft(second).dy, lessThanOrEqualTo(640));
    expect(tester.getTopLeft(second).dy, greaterThan(200));
    expect(tester.takeException(), isNull);

    await tester.tap(second);
    await tester.pumpAndSettle();
    expect(changed?.id, 'b');
    expect(find.text('切换服务器'), findsNothing);
  });

  testWidgets('server switch is disabled while a room is active', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServerProfilePicker(
            profiles: servers,
            selected: servers.first,
            onSelected: _noSelection,
            isNight: true,
            enabled: false,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('server-profile-picker')));
    await tester.pump();
    expect(find.text('切换服务器'), findsNothing);
  });
}

void _noSelection(ServerProfile value) {}
