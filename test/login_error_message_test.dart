import 'dart:async';
import 'dart:io';

import 'package:employee_attendance/utils/user_facing_error.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the login error-message contract.
///
/// A field user who mistypes their password must be told the password is
/// wrong. Telling them the network is down sends them off debugging Wi-Fi for
/// a problem that is neither network nor password-shape.
void main() {
  group('UserFacingError.forLogin', () {
    test('a 401 says the credentials are wrong, not that the network is down',
        () {
      expect(
        UserFacingError.forLogin(statusCode: 401),
        UserFacingError.wrongCredentials,
      );
      expect(
        UserFacingError.forLogin(statusCode: 403),
        UserFacingError.wrongCredentials,
      );
    });

    test('recognises a credential rejection that arrives without a 401', () {
      expect(
        UserFacingError.forLogin(
          statusCode: 200,
          rawMessage: 'These credentials do not match our records.',
        ),
        UserFacingError.wrongCredentials,
      );
      expect(
        UserFacingError.forLogin(statusCode: 500, rawMessage: 'unauthorized'),
        UserFacingError.wrongCredentials,
      );
    });

    test('rate limiting is reported as rate limiting', () {
      expect(
        UserFacingError.forLogin(statusCode: 429),
        UserFacingError.tooManyAttempts,
      );
    });

    test('a server fault says the server is down, not that the user is wrong',
        () {
      expect(
        UserFacingError.forLogin(statusCode: 503),
        UserFacingError.serverDown,
      );
    });

    test('never reports a credential problem as a network problem', () {
      final messages = <String>{
        for (final code in [400, 401, 403, 422, 429, 500, 503])
          UserFacingError.forLogin(statusCode: code),
        for (final text in [
          'invalid email or password',
          'unauthenticated',
          'login failed',
        ])
          UserFacingError.forLogin(statusCode: 200, rawMessage: text),
      };

      expect(messages, isNot(contains(UserFacingError.noInternet)));
    });
  });

  group('UserFacingError.forException', () {
    test('maps an unreachable socket to no internet', () {
      expect(
        UserFacingError.forException(
          const SocketException('Connection refused'),
        ),
        UserFacingError.noInternet,
      );
    });

    test('a TLS failure says the server is unreachable, not that Wi-Fi is out',
        () {
      expect(
        UserFacingError.forException(const HandshakeException('bad cert')),
        UserFacingError.serverDown,
      );
    });

    test('an unrecognised error stays generic rather than blaming the network',
        () {
      // A bug in the app must never be reported to a field user as
      // "no internet" — that sends them to debug hardware that is fine.
      expect(
        UserFacingError.forException(StateError('bad state')),
        UserFacingError.generic,
      );
      expect(
        UserFacingError.forException(FormatException('bad json')),
        UserFacingError.generic,
      );
    });
  });

  group('UserFacingError.looksLikeCredentialError', () {
    test('is case insensitive and tolerant of null', () {
      expect(UserFacingError.looksLikeCredentialError(null), isFalse);
      expect(
        UserFacingError.looksLikeCredentialError('INVALID CREDENTIALS'),
        isTrue,
      );
    });
  });

  group('slow server is never reported as an offline device', () {
    test('a timeout says the server is slow, not that Wi-Fi is down', () {
      // The production host has been measured taking ~20s to complete a TCP
      // connect while healthy. Reporting that as "no internet" sends a field
      // user to debug hardware that is working fine.
      expect(
        UserFacingError.forException(TimeoutException('slow connect')),
        UserFacingError.serverSlow,
      );
    });

    test('the slow-server message invites a retry, not a network check', () {
      expect(
        UserFacingError.serverSlow.toLowerCase(),
        contains('try again'),
      );
      expect(
        UserFacingError.serverSlow.toLowerCase(),
        isNot(contains('network')),
      );
      expect(
        UserFacingError.serverSlow,
        isNot(UserFacingError.noInternet),
      );
    });

    test('an unreachable socket still says no internet', () {
      // A genuine connection refusal is a real network problem and should be
      // reported as one.
      expect(
        UserFacingError.forException(
          const SocketException('Failed host lookup'),
        ),
        UserFacingError.noInternet,
      );
    });
  });
}
