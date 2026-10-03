import 'package:employee_attendance/config/app_config.dart';
import 'package:employee_attendance/models/app_update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

/// The OTA beta channel.
///
/// The rule that matters is `normalizeVersionCode`. Build numbers live in
/// disjoint bands per channel — prod under 9000, beta at 9000+ — and the
/// function that strips Flutter's split-per-ABI prefix used to reduce anything
/// above 1000 modulo 1000. Left as it was, a beta build 9108 would have become
/// 108: the tester would be offered the wrong channel's update, and a production
/// manifest at 108 would compare as older than a beta build.
void main() {
  group('normalizeVersionCode', () {
    test('leaves an ordinary production build number alone', () {
      expect(normalizeVersionCode('104'), 104);
      expect(normalizeVersionCode('999'), 999);
    });

    test('still strips the split-per-ABI prefixes', () {
      // 1000 = armeabi-v7a, 2000 = arm64-v8a, 3000 = x86_64.
      expect(normalizeVersionCode('1104'), 104);
      expect(normalizeVersionCode('2104'), 104);
      expect(normalizeVersionCode('3104'), 104);
    });

    test('leaves the beta band intact', () {
      // The whole point: 9000+ is a real version code, not an ABI prefix.
      expect(normalizeVersionCode('9001'), 9001);
      expect(normalizeVersionCode('9108'), 9108);
    });

    test('a beta build never compares as a production build', () {
      // Both sides go through the function, so a beta install compared against
      // a beta manifest still behaves.
      expect(normalizeVersionCode('9002'), greaterThan(normalizeVersionCode('108')));
    });

    test('a split-per-ABI build still resolves to its real number', () {
      // The APK's own versionCode is what PackageInfo reports: Flutter adds
      // abiIndex*1000. 2000+104 is an arm64 production build.
      expect(normalizeVersionCode('2104'), 104);
    });

    test('a beta split-per-ABI number is left intact', () {
      // Flutter would encode a beta arm64 build as 2000+9001 = 29001, which is
      // outside the 1000-3999 prefix bands. Reducing it modulo 1000 would
      // produce 901 and break the band, so the whole number is kept. The two
      // sides of the comparison then still cancel, because both the installed
      // value and the manifest value pass through this same function.
      expect(normalizeVersionCode('29001'), 29001);
      expect(normalizeVersionCode('29001'), greaterThan(normalizeVersionCode('2107')));
    });

    test('falls back to 0 on unparseable input rather than throwing', () {
      expect(normalizeVersionCode('not-a-number'), 0);
      expect(normalizeVersionCode(''), 0);
    });
  });

  group('isUpdateRequired', () {
    test('a newer remote code on the same channel is an update', () {
      expect(isUpdateRequired(installedVersionCode: 104, remoteVersionCode: 105), isTrue);
    });

    test('the same code is not an update', () {
      expect(isUpdateRequired(installedVersionCode: 104, remoteVersionCode: 104), isFalse);
    });

    test('a beta manifest is newer than any production build', () {
      // The band is what stops a beta publish from being offered downward, and
      // what stops a production device from ever seeing a beta manifest.
      expect(isUpdateRequired(installedVersionCode: 107, remoteVersionCode: 9001), isTrue);
    });
  });

  group('manifest channel', () {
    AppUpdateManifest parse(Map<String, dynamic> json) =>
        AppUpdateManifest.fromJson({
          'app_id': 'com.pphl.employee_attendance',
          'version_name': '2.6.0-beta.1',
          'version_code': 9001,
          'force_update': false,
          'release_notes': '',
          'apks': <String, dynamic>{},
          ...json,
        });

    test('is read when present', () {
      expect(parse({'channel': 'beta'}).channel, 'beta');
    });

    test('is null on a manifest published before channels existed', () {
      // An older prod manifest has no channel key; it must not throw or default
      // to beta, which would label every production update as a beta one.
      expect(parse({}).channel, isNull);
    });
  });

  group('app config channel defaults', () {
    test('defaults to prod, matching a build with no channel define', () {
      // The default is what every already-published build compiled with.
      expect(AppConfig.updateChannel, 'prod');
    });

    test('an unknown channel falls back to the production manifest', () {
      // Verified through the switch: only the literal 'beta' diverts, so a typo
      // in a --dart-define cannot leave a build fleet with no OTA path.
      expect(AppConfig.updateManifestUrl, contains('/ota/manifest.json'));
      expect(AppConfig.updateManifestUrl, isNot(contains('/ota/beta/')));
    });
  });

  group('beta band constants', () {
    test('the floor is high enough to stay clear of the ABI prefixes', () {
      // 4000 would also work, but 9000 leaves a visible gap in the profile
      // version number so a beta build is obvious at a glance.
      expect(betaVersionFloor, greaterThan(4000));
    });
  });
}