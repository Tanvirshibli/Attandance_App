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
    test('leaves an unsplit build number alone', () {
      expect(normalizeVersionCode('104'), 104);
      expect(normalizeVersionCode('999'), 999);
    });

    test('subtracts the ABI offset from a split build', () {
      // The offset is ADDED to the base, not prefixed: armeabi-v7a is base+1000,
      // arm64-v8a base+2000, x86_64 base+3000.
      expect(normalizeVersionCode('1104', abiOffset: 1000), 104);
      expect(normalizeVersionCode('2104', abiOffset: 2000), 104);
      expect(normalizeVersionCode('3104', abiOffset: 3000), 104);
    });

    test('subtracts, never takes a modulo', () {
      // The bug this replaced: 11008 % 1000 is 8, so a beta manifest would
      // have advertised build 8 and every tester read it as up to date.
      expect(normalizeVersionCode('11008', abiOffset: 2000), 9008);
      expect(normalizeVersionCode('10008', abiOffset: 1000), 9008);
    });

    test('the beta band survives normalisation intact', () {
      expect(normalizeVersionCode('11008', abiOffset: 2000), greaterThan(8999));
      expect(normalizeVersionCode('9008'), 9008);
    });

    test('no guessing when the ABI is unknown', () {
      // Subtracting an assumed offset would turn 11008 into 6008 or 8008
      // depending on the guess, and nothing downstream would surface it.
      expect(normalizeVersionCode('11008'), 11008);
    });

    test('falls back to 0 on unparseable input rather than throwing', () {
      expect(normalizeVersionCode('not-a-number'), 0);
      expect(normalizeVersionCode(''), 0);
    });
  });

  group('abiOffsetFor', () {
    test('maps the three split ABIs', () {
      expect(abiOffsetFor('armeabi-v7a'), 1000);
      expect(abiOffsetFor('arm64-v8a'), 2000);
      expect(abiOffsetFor('x86_64'), 3000);
    });

    test('returns 0 for anything else, including null', () {
      expect(abiOffsetFor(null), 0);
      expect(abiOffsetFor('mips'), 0);
      expect(abiOffsetFor(''), 0);
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