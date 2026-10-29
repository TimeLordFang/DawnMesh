import 'package:dawn_mesh/core/platform/external_link_launcher.dart';
import 'package:dawn_mesh/ui/pages/about_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.dawnmesh.intercom/external_links');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('About privacy button opens the public policy URL', (
    tester,
  ) async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return true;
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: const AboutPage(isNight: false),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.widgetWithText(OutlinedButton, 'Privacy policy');
    await tester.scrollUntilVisible(button, 250);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(received?.method, 'openUrl');
    expect(received?.arguments, {
      'url': 'https://timelordfang.github.io/DawnMesh/privacy/',
    });
  });

  test('a missing browser is reported as a recoverable failure', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'NO_BROWSER');
    });
    expect(await ExternalLinkLauncher.openPrivacyPolicy(), isFalse);
  });
}
