import 'package:flutter_test/flutter_test.dart';

import 'package:employee_attendance/models/app_update_manifest.dart';

void main() {
  group('AppUpdateManifest', () {
    test('parses manifest with both ABIs', () {
      final manifest = AppUpdateManifest.fromJson({
        'app_id': 'com.pphl.employee_attendance',
        'version_name': '2.2.3',
        'version_code': 35,
        'force_update': true,
        'release_notes': 'OTA update',
        'published_at': '2026-08-12T08:00:00Z',
        'apks': {
          'arm64-v8a': {
            'url': 'https://example.com/arm64.apk',
            'size_bytes': 1000,
            'sha256': 'abc',
          },
          'armeabi-v7a': {
            'url': 'https://example.com/arm.apk',
            'size_bytes': 900,
            'sha256': 'def',
          },
        },
      });

      expect(manifest.versionCode, 35);
      expect(manifest.forceUpdate, isTrue);
      expect(manifest.apks.length, 2);
      expect(manifest.resolveApk(preferredAbi: 'arm64-v8a')?.url,
          'https://example.com/arm64.apk');
    });

    test('resolveApk falls back to armeabi-v7a', () {
      final manifest = AppUpdateManifest.fromJson({
        'app_id': 'com.pphl.employee_attendance',
        'version_name': '2.2.3',
        'version_code': 35,
        'force_update': true,
        'release_notes': '',
        'apks': {
          'armeabi-v7a': {
            'url': 'https://example.com/arm.apk',
            'size_bytes': 900,
            'sha256': 'def',
          },
        },
      });

      expect(
        manifest.resolveApk(preferredAbi: 'arm64-v8a')?.url,
        'https://example.com/arm.apk',
      );
    });
  });

  group('version compare', () {
    test('normalizeVersionCode handles ABI offset', () {
      expect(normalizeVersionCode('1034'), 34);
      expect(normalizeVersionCode('34'), 34);
    });

    test('isUpdateRequired when remote is newer', () {
      expect(
        isUpdateRequired(installedVersionCode: 33, remoteVersionCode: 34),
        isTrue,
      );
      expect(
        isUpdateRequired(installedVersionCode: 34, remoteVersionCode: 34),
        isFalse,
      );
    });
  });
}
