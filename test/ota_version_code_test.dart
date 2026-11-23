import 'package:flutter_test/flutter_test.dart';

import 'package:employee_attendance/models/app_update_manifest.dart';
import 'package:employee_attendance/services/app_update_service.dart';

void main() {
  group('normalizeAbiName', () {
    test('maps platform spellings onto the split names', () {
      expect(normalizeAbiName('arm64-v8a'), 'arm64-v8a');
      expect(normalizeAbiName('ARM64'), 'arm64-v8a');
      expect(normalizeAbiName('aarch64'), 'arm64-v8a');
      expect(normalizeAbiName('armeabi-v7a'), 'armeabi-v7a');
      expect(normalizeAbiName('armv7l'), 'armeabi-v7a');
      expect(normalizeAbiName('x86_64'), 'x86_64');
      expect(normalizeAbiName(''), '');
      expect(normalizeAbiName(null), '');
    });
  });

  group('resolveInstalledVersionCode', () {
    test('known ABIs subtract their split offset', () {
      expect(
        resolveInstalledVersionCode('11041', abi: 'arm64-v8a', channel: 'beta'),
        9041,
      );
      expect(
        resolveInstalledVersionCode('10041',
            abi: 'armeabi-v7a', channel: 'beta'),
        9041,
      );
      expect(
        resolveInstalledVersionCode('2126', abi: 'arm64-v8a', channel: 'prod'),
        126,
      );
    });

    test('an unrecognised ABI recovers the offset from the channel band', () {
      expect(
        resolveInstalledVersionCode('11041', abi: 'weird-abi', channel: 'beta'),
        9041,
      );
      expect(resolveInstalledVersionCode('10041', abi: '', channel: 'beta'),
          9041);
      expect(resolveInstalledVersionCode('1126', abi: 'nonsense', channel: 'prod'),
          126);
      expect(resolveInstalledVersionCode('2126', abi: null, channel: 'prod'),
          126);
    });

    test('a build without an ABI offset is left in its own band', () {
      expect(resolveInstalledVersionCode('9041', abi: 'arm64', channel: 'beta'),
          9041);
      expect(resolveInstalledVersionCode('126', abi: '', channel: 'prod'), 126);
    });

    test('garbage input is zero, not an exception', () {
      expect(
        resolveInstalledVersionCode('not-a-number',
            abi: 'arm64-v8a', channel: 'beta'),
        0,
      );
    });

    test('a newer beta is offered to an un-normalised 11xxx install', () {
      final installed = resolveInstalledVersionCode('11040',
          abi: 'unknown', channel: 'beta');
      expect(installed, 9040);
      expect(
        isUpdateRequired(installedVersionCode: installed, remoteVersionCode: 9042),
        isTrue,
      );
    });
  });

  group('AppUpdateCheckResult', () {
    test('an up-to-date result keeps the numbers it compared', () {
      const result = AppUpdateCheckResult.upToDate(
        installedVersionCode: 9041,
        remoteVersionCode: 9042,
        installedAbi: 'arm64-v8a',
        rawInstalledBuildNumber: '11041',
      );

      expect(result.needsUpdate, isFalse);
      expect(result.installedVersionCode, 9041);
      expect(result.remoteVersionCode, 9042);
      expect(result.rawInstalledBuildNumber, '11041');
    });
  });
}
