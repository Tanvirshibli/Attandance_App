import 'package:employee_attendance/models/endpoint_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EndpointConfig.fromJson — empty remote payload', () {
    // The zkteco host answers this when it has nothing published. Treating it
    // as authoritative cached the app into falling back on every URL resolve.
    const emptyPayload = <String, dynamic>{
      'version': 0,
      'updated_at': null,
      'bases': <dynamic>[],
      'endpoints': <dynamic>[],
      'features': <dynamic>[],
    };

    test('parses an empty payload into empty collections', () {
      final config = EndpointConfig.fromJson(emptyPayload);

      expect(config.endpoints, isEmpty);
      expect(config.bases, isEmpty);
      expect(config.version, 0);
    });

    test('urlFor returns null so the caller falls back', () {
      final config = EndpointConfig.fromJson(emptyPayload);

      expect(config.urlFor('auth.login'), isNull);
      expect(config.urlFor('auth.profile'), isNull);
    });

    test('an empty payload carries no feature overrides', () {
      final config = EndpointConfig.fromJson(emptyPayload);

      expect(config.isFeatureEnabled('payment.enabled'), isFalse);
      expect(config.isFeatureEnabled('payment.enabled', defaultValue: true),
          isTrue);
    });
  });

  group('EndpointConfig.fromJson — populated payload', () {
    test('exposes endpoints and bases as maps', () {
      final config = EndpointConfig.fromJson({
        'version': 3,
        'updated_at': '2026-09-27T00:00:00Z',
        'bases': {'hrm': 'https://hrm.example.com'},
        'endpoints': {
          'auth.login': {
            'method': 'POST',
            'url': 'https://hrm.example.com/api/v1/a/login',
            'backend': 'hrm',
          },
        },
        'features': {'payment.enabled': true},
      });

      expect(config.version, 3);
      expect(config.bases['hrm'], 'https://hrm.example.com');
      expect(config.urlFor('auth.login'),
          'https://hrm.example.com/api/v1/a/login');
      expect(config.isFeatureEnabled('payment.enabled'), isTrue);
    });

    test('a populated payload is distinguishable from an empty one', () {
      // This is the exact predicate the service now gates caching on.
      final populated = EndpointConfig.fromJson({
        'version': 1,
        'bases': <String, dynamic>{'hrm': 'https://hrm.example.com'},
        'endpoints': <String, dynamic>{},
        'features': <String, dynamic>{},
      });
      final empty = EndpointConfig.fromJson({
        'version': 0,
        'bases': <dynamic>[],
        'endpoints': <dynamic>[],
        'features': <dynamic>[],
      });

      expect(populated.endpoints.isNotEmpty || populated.bases.isNotEmpty,
          isTrue);
      expect(empty.endpoints.isNotEmpty || empty.bases.isNotEmpty, isFalse);
    });
  });

  group('sales.chicksBooking.enabled — the chick booking freeze', () {
    // Chick booking posting is hidden and disabled until the rework is
    // confirmed. The server has never published this key, so the
    // resolution must fail closed for every device and every offline
    // fallback path.
    test('a config that never heard of the key fails closed', () {
      final config = EndpointConfig.fromJson({
        'version': 1,
        'bases': <String, dynamic>{},
        'endpoints': <String, dynamic>{},
        'features': <String, dynamic>{'sales.enabled': true},
      });

      expect(
        config.isFeatureEnabled('sales.chicksBooking.enabled',
            defaultValue: false),
        isFalse,
      );
    });

    test('reports enabled only when the server explicitly turns it on', () {
      final config = EndpointConfig.fromJson({
        'version': 1,
        'bases': <String, dynamic>{},
        'endpoints': <String, dynamic>{},
        'features': <String, dynamic>{
          'sales.chicksBooking.enabled': true,
        },
      });

      expect(
        config.isFeatureEnabled('sales.chicksBooking.enabled',
            defaultValue: false),
        isTrue,
      );
    });

    test('an explicit false stays disabled', () {
      final config = EndpointConfig.fromJson({
        'version': 1,
        'bases': <String, dynamic>{},
        'endpoints': <String, dynamic>{},
        'features': <String, dynamic>{
          'sales.chicksBooking.enabled': false,
        },
      });

      expect(
        config.isFeatureEnabled('sales.chicksBooking.enabled',
            defaultValue: false),
        isFalse,
      );
    });
  });
}
