import 'package:employee_attendance/utils/user_facing_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserFacingError.forPunchRefusal', () {
    test('names each documented refusal instead of hiding it', () {
      const expected = {
        'gps_required': 'Location is required',
        'gps_untrusted': 'location looks fake',
        'client_time_required': 'phone time is needed',
        'device_time_untrusted': 'phone clock is wrong',
        'app_outdated': 'too old to punch',
        'biometric_authorization_required': 'fresh face or fingerprint',
      };

      expected.forEach((code, fragment) {
        final message = UserFacingError.forPunchRefusal(
          statusCode: 422,
          rawMessage: code,
        );
        expect(
          message.toLowerCase(),
          contains(fragment.toLowerCase()),
          reason: '$code must name its real reason',
        );
        expect(message, isNot(UserFacingError.generic));
        expect(message, isNot(UserFacingError.serverDown));
      });
    });

    test('passes a shift-window refusal through verbatim', () {
      const window =
          'Check-in is closed. Your "Wing - Head Office" shift started at 09:00 AM '
          'and the 15-minute grace period ended at 09:15 AM.';

      expect(
        UserFacingError.forPunchRefusal(statusCode: 422, rawMessage: window),
        window,
      );
    });

    test('still reports a genuine 5xx as an outage', () {
      expect(
        UserFacingError.forPunchRefusal(statusCode: 500, rawMessage: null),
        UserFacingError.serverDown,
      );
    });

    test('is case-insensitive about the refusal code', () {
      expect(
        UserFacingError.forPunchRefusal(statusCode: 422, rawMessage: 'GPS_REQUIRED'),
        contains('Location is required'),
      );
    });
  });

  group('UserFacingFailure', () {
    test('a 5xx is an outage worth retrying elsewhere', () {
      final failure =
          UserFacingFailure.fromSubmit(statusCode: 500, rawMessage: null);

      expect(failure.isOutage, isTrue);
    });

    test('a 4xx is a decision, never an outage', () {
      for (final code in [400, 401, 403, 409, 422, 429]) {
        final failure =
            UserFacingFailure.fromSubmit(statusCode: code, rawMessage: null);

        expect(
          failure.isOutage,
          isFalse,
          reason: '$code must not fall through to another backend',
        );
      }
    });

    test('a refused biometric punch is not reported as an outage', () {
      final failure = UserFacingFailure.fromSubmit(
        statusCode: 422,
        rawMessage: 'biometric_authorization_required',
      );

      expect(failure.isOutage, isFalse);
      expect(failure.message, isNot(UserFacingError.serverDown));
    });
  });
}
