import 'package:dawn_mesh/core/internet/internet_models.dart';
import 'package:dawn_mesh/core/internet/server_profile_store.dart';
import 'package:dawn_mesh/ui/pages/server_settings_page.dart';
import 'package:dawn_mesh/ui/pages/settings_page.dart';
import 'package:dawn_mesh/ui/pages/internet_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'servers share one settings path and saved credentials survive CRUD',
    (tester) async {
      final store = ServerProfileStore();
      await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
      await tester.tap(find.byKey(const ValueKey('settings-servers')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-server')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '我的服务器');
      await tester.enterText(
        find.byType(TextField).at(1),
        'https://talk.example.test/',
      );
      await tester.enterText(
        find.byType(TextField).at(2),
        'private-test-token',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final saved = (await store.loadProfiles()).single;
      expect(saved.baseUrl, 'https://talk.example.test');
      expect(saved.accessToken, 'private-test-token');
      expect(await store.loadSelectedId(), saved.id);
      expect(find.text('private-test-token'), findsNothing);

      await tester.tap(find.byKey(ValueKey('edit-server-${saved.id}')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '改名后');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect((await store.loadProfiles()).single.id, saved.id);
      expect((await store.loadProfiles()).single.name, '改名后');
      expect(
        (await store.loadProfiles()).single.accessToken,
        saved.accessToken,
      );

      await tester.tap(find.byKey(ValueKey('delete-server-${saved.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await store.loadProfiles(), hasLength(1));
      await tester.tap(find.byKey(ValueKey('delete-server-${saved.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(await store.loadProfiles(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'active server cannot be edited or removed, adding does not switch it',
    (tester) async {
      final store = ServerProfileStore();
      const active = ServerProfile(
        id: 'active',
        name: '通话服务器',
        baseUrl: 'https://active.example.test',
      );
      await store.saveProfiles([active]);
      await store.saveSelectedId(active.id);
      await tester.pumpWidget(
        const MaterialApp(home: ServerSettingsPage(lockedServerId: 'active')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('edit-server-active')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('delete-server-active')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('add-server')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).at(1),
        'https://second.example.test',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(await store.loadProfiles(), hasLength(2));
      expect(await store.loadSelectedId(), active.id);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'returning from shared settings reloads the public lobby profiles',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: InternetHomePage(isNight: false, nickname: 'test'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-servers')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-server')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '返回后可见');
      await tester.enterText(
        find.byType(TextField).at(1),
        'https://back.example.test',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('返回后可见'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
