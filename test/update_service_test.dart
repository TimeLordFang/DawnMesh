import 'dart:io';

import 'package:dawn_mesh/core/update/update_service.dart';
import 'package:dawn_mesh/l10n/app_strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app and changelog versions match pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final packageVersion = RegExp(
      r'^version:\s*([^+\s]+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);

    expect(UpdateService.currentVersion, packageVersion);
    expect(AppStrings.zh.changelogBody, startsWith(packageVersion!));
    expect(AppStrings.en.changelogBody, startsWith(packageVersion));
  });

  group('UpdateService SemVer Comparison Tests', () {
    test(
      'Older pre-release (alpha.9) is NOT newer than current (alpha.10)',
      () {
        expect(
          UpdateService.isNewer('0.1.0-alpha.9', '0.1.0-alpha.10'),
          isFalse,
        );
        expect(
          UpdateService.isNewer('v0.1.0-alpha.9', '0.1.0-alpha.10'),
          isFalse,
        );
      },
    );

    test('Identical version is NOT newer', () {
      expect(
        UpdateService.isNewer('0.1.0-alpha.10', '0.1.0-alpha.10'),
        isFalse,
      );
      expect(
        UpdateService.isNewer('v0.1.0-alpha.10', '0.1.0-alpha.10'),
        isFalse,
      );
    });

    test('Newer pre-release or channel (alpha.11, beta.1, rc.1) IS newer than alpha.10', () {
      expect(UpdateService.isNewer('0.1.0-alpha.11', '0.1.0-alpha.10'), isTrue);
      expect(
        UpdateService.isNewer('v0.1.0-alpha.11', '0.1.0-alpha.10'),
        isTrue,
      );
      expect(UpdateService.isNewer('0.1.0-beta.1', '0.1.0-alpha.10'), isTrue);
      expect(UpdateService.isNewer('0.1.0-rc.1', '0.1.0-alpha.10'), isTrue);
    });

    test('Formal release 0.1.0 is newer than pre-release 0.1.0-alpha.10', () {
      expect(UpdateService.isNewer('0.1.0', '0.1.0-alpha.10'), isTrue);
      expect(UpdateService.isNewer('v0.1.0', '0.1.0-alpha.10'), isTrue);
    });

    test('Major and minor version bumps are newer', () {
      expect(UpdateService.isNewer('0.2.0-alpha.1', '0.1.0-alpha.10'), isTrue);
      expect(UpdateService.isNewer('1.0.0', '0.1.0-alpha.10'), isTrue);
      expect(UpdateService.isNewer('0.0.9', '0.1.0-alpha.10'), isFalse);
    });

    test('Build metadata (+...) is handled correctly', () {
      expect(UpdateService.isNewer('0.1.0+99', '0.1.0+1'), isFalse);
      expect(UpdateService.isNewer('0.1.1+1', '0.1.0+99'), isTrue);
    });
  });

  group('GitHub Releases response', () {
    test('selects the highest non-draft release including prereleases', () {
      final state = UpdateService.stateFromGithubResponse(<Object?>[
        <String, Object?>{
          'tag_name': 'v0.1.0-dev.17',
          'html_url': 'https://github.com/TimeLordFang/DawnMesh/releases/tag/v0.1.0-dev.17',
          'body': 'new release',
          'draft': false,
          'prerelease': true,
        },
        <String, Object?>{
          'tag_name': 'v9.9.9',
          'html_url':
              'https://github.com/TimeLordFang/DawnMesh/releases/tag/v9.9.9',
          'draft': true,
        },
      ], currentVersion: '0.1.0-dev.16');

      expect(state, isA<UpdateAvailable>());
      final available = state as UpdateAvailable;
      expect(available.versionName, '0.1.0-dev.17');
      expect(available.releaseNotes, 'new release');
    });

    test('rejects release URLs outside the DawnMesh GitHub repository', () {
      final state = UpdateService.stateFromGithubResponse(<Object?>[
        <String, Object?>{
          'tag_name': 'v99.0.0',
          'html_url': 'https://example.com/fake.apk',
          'draft': false,
        },
      ], currentVersion: '0.1.0-dev.16');

      expect(state, isA<UpdateUpToDate>());
    });
  });
}
