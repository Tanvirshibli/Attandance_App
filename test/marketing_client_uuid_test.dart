import 'package:employee_attendance/data/marketing_demo_masters.dart';
import 'package:flutter_test/flutter_test.dart';

/// The visit's `client_uuid` is written into a Postgres `uuid` column.
///
/// The previous `mkt-<hex>` id passed the API's `nullable|string|max:64` rule
/// and then died at the insert (`SQLSTATE 22P02`), so every dealer visit failed
/// with a 500 that the app showed as "Server is unreachable". These pin the
/// value's shape so a reintroduction of a non-UUID id fails here instead.
void main() {
  // RFC 4122 v4: 8-4-4-4-12 lowercase hex, version nibble 4, variant 8/9/a/b.
  final uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  group('marketingNewClientUuid', () {
    test('returns an RFC 4122 v4 UUID', () {
      expect(marketingNewClientUuid(), matches(uuidV4));
    });

    test('keeps the version and variant nibbles fixed', () {
      for (var i = 0; i < 50; i++) {
        final uuid = marketingNewClientUuid();
        expect(uuid[14], '4', reason: 'version nibble must be 4');
        expect(
          '89ab'.contains(uuid[19]),
          isTrue,
          reason: 'variant nibble must be one of 8, 9, a, b',
        );
      }
    });

    test('never emits the retired mkt- prefix', () {
      for (var i = 0; i < 50; i++) {
        expect(marketingNewClientUuid().startsWith('mkt-'), isFalse);
      }
    });

    test('is unique across calls', () {
      final seen = <String>{};
      for (var i = 0; i < 200; i++) {
        expect(seen.add(marketingNewClientUuid()), isTrue);
      }
    });
  });
}
