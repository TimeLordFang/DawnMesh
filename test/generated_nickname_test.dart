import 'dart:convert';
import 'dart:math';

import 'package:dawn_mesh/core/audio/audio_io.dart';
import 'package:dawn_mesh/core/preferences/generated_nickname.dart';
import 'package:dawn_mesh/ui/pages/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty and legacy default nicknames require generation', () {
    expect(GeneratedNickname.needsGeneration(null), isTrue);
    expect(GeneratedNickname.needsGeneration('  '), isTrue);
    expect(GeneratedNickname.needsGeneration('探索者'), isTrue);
    expect(GeneratedNickname.needsGeneration('Explorer'), isTrue);
    expect(GeneratedNickname.needsGeneration('EXPLORER'), isTrue);
    expect(GeneratedNickname.needsGeneration('晨风旅人527'), isFalse);
  });

  test(
    'generated nicknames are readable, distinct from defaults and bounded',
    () {
      final zh = GeneratedNickname.generate(
        isEnglish: false,
        random: Random(7),
      );
      final en = GeneratedNickname.generate(isEnglish: true, random: Random(7));

      expect(zh, matches(RegExp(r'^[\u4e00-\u9fff]+\d{3}$')));
      expect(en, matches(RegExp(r'^[A-Za-z]+ [A-Za-z]+ \d{3}$')));
      expect(GeneratedNickname.needsGeneration(zh), isFalse);
      expect(GeneratedNickname.needsGeneration(en), isFalse);
      expect(utf8.encode(zh).length, lessThanOrEqualTo(48));
      expect(utf8.encode(en).length, lessThanOrEqualTo(48));
    },
  );

  testWidgets('home replaces and persists a legacy default nickname', (
    tester,
  ) async {
    const channel = MethodChannel('dev.dawnmesh.intercom/preferences');
    String? persisted;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getNickname') return 'Explorer';
      if (call.method == 'setNickname') {
        persisted = (call.arguments as Map)['nickname'] as String;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeContent(
            isNight: false,
            stage: const AlwaysStoppedAnimation(0),
            audioIo: MockAudioIo(),
            onEnterRoom: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final field = tester.widget<TextField>(find.byType(TextField).first);
    final nickname = field.controller!.text;
    expect(GeneratedNickname.needsGeneration(nickname), isFalse);
    expect(nickname, isNot('Explorer'));
    expect(persisted, nickname);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
