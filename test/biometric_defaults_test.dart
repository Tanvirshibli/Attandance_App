import 'package:employee_attendance/services/biometric_api_service.dart';
import 'package:employee_attendance/services/biometric_preferences_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('biometric combinations', () {
    test('both check-in methods on is accepted', () {
      const prefs = BiometricPreferencesData(
        loginFace: true,
        loginFingerprint: true,
        checkinFace: true,
        checkinFingerprint: true,
      );

      expect(BiometricPreferencesService.invalidCombinationReason(prefs), isNull);
    });

    test('face-only check-in is accepted', () {
      const prefs = BiometricPreferencesData(
        loginFace: true,
        loginFingerprint: false,
        checkinFace: true,
        checkinFingerprint: false,
      );

      expect(BiometricPreferencesService.invalidCombinationReason(prefs), isNull);
    });

    test('fingerprint-only check-in is accepted', () {
      const prefs = BiometricPreferencesData(
        loginFace: false,
        loginFingerprint: true,
        checkinFace: false,
        checkinFingerprint: true,
      );

      expect(BiometricPreferencesService.invalidCombinationReason(prefs), isNull);
    });

    test('turning both check-in methods off is refused', () {
      const prefs = BiometricPreferencesData(
        loginFace: true,
        loginFingerprint: true,
        checkinFace: false,
        checkinFingerprint: false,
      );

      final reason =
          BiometricPreferencesService.invalidCombinationReason(prefs);

      expect(reason, isNotNull);
      expect(reason, contains('check-in'));
    });

    test('turning both login methods off is refused', () {
      const prefs = BiometricPreferencesData(
        loginFace: false,
        loginFingerprint: false,
        checkinFace: true,
        checkinFingerprint: true,
      );

      expect(
        BiometricPreferencesService.invalidCombinationReason(prefs),
        isNotNull,
      );
    });
  });

  group('preference payloads', () {
    test('an absent preference never reads as on', () {
      expect(BiometricPreferencesData.fromJson(<String, dynamic>{}), isNull);

      final parsed = BiometricPreferencesData.fromJson(<String, dynamic>{
        'login': <String, dynamic>{'face': true},
        'checkin': <String, dynamic>{},
      });

      expect(parsed, isNotNull);
      expect(parsed!.loginFace, isTrue);
      expect(parsed.loginFingerprint, isFalse);
      expect(parsed.checkinFace, isFalse);
      expect(parsed.checkinFingerprint, isFalse);
    });

    test('the wire shape is the nested login/checkin object', () {
      const prefs = BiometricPreferencesData(
        loginFace: true,
        loginFingerprint: false,
        checkinFace: true,
        checkinFingerprint: true,
      );

      final json = prefs.toJson();

      expect(json['login'], <String, dynamic>{
        'face': true,
        'fingerprint': false,
      });
      expect(json['checkin'], <String, dynamic>{
        'face': true,
        'fingerprint': true,
      });
    });
  });
}
