import 'package:dawn_mesh/core/audio/audio_io.dart';
import 'package:dawn_mesh/ui/pages/fusion_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final width in [360.0, 430.0]) {
    testWidgets('fusion entrance works without a server on $width px screen', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: FusionHomePage(
            audioIo: MockAudioIo(),
            nickname: '离线用户',
            isNight: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      final create = find.byKey(const ValueKey('create-fusion-room'));
      expect(tester.widget<FilledButton>(create).onPressed, isNotNull);
      expect(find.text('可加入的融合房'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(create);
      await tester.pump();
      expect(find.text('创建房间'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
