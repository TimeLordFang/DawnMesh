import 'dart:convert';
import 'dart:io';

import 'package:dawn_mesh/core/audio/audio_io.dart';
import 'package:dawn_mesh/ui/pages/fusion_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'one room tap opens one invite and cancel permits another attempt',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FusionHomePage(
            audioIo: MockAudioIo(),
            nickname: '成员',
            isNight: false,
          ),
        ),
      );
      final roomId = base64UrlEncode(List.filled(32, 7)).replaceAll('=', '');
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        final socket = await RawDatagramSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        socket.send(
          utf8.encode(
            jsonEncode({
              'magic': 'DAWN_MESH_FUSION_V1',
              'roomId': roomId,
              'roomName': '同网融合房',
              'hostNickname': '房主',
              'port': 8991,
              'members': 1,
            }),
          ),
          InternetAddress.loopbackIPv4,
          8992,
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));
        socket.close();
      });
      await tester.pump();
      final room = find.byKey(ValueKey('fusion-room-$roomId'));
      expect(room, findsOneWidget);
      await tester.ensureVisible(room);
      final tapAgain = tester.widget<ListTile>(room).onTap!;
      await tester.tap(room);
      tapAgain(); // A second tap before rebuilding cannot stack another dialog.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('输入房间邀请码'), findsOneWidget);
      expect(find.byKey(const ValueKey('room-invite-input')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('create-fusion-room')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(room);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('输入房间邀请码'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

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
