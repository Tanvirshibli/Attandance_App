import 'package:employee_attendance/models/auth_user_profile.dart';
import 'package:employee_attendance/models/zone_models.dart';
import 'package:employee_attendance/models/zone_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Zone C (Rajshahi/Bogura/Rangpur) and Zone A (Gazipur/Mymensingh/Tangail),
  // mirroring the live `get-zone` payload.
  const zoneC = SalesZone(
    id: 3,
    zoneName: 'Zone C',
    districts: [
      ZoneDistrict(id: 18, name: 'Bogura'),
      ZoneDistrict(id: 24, name: 'Rajshahi'),
      ZoneDistrict(id: 32, name: 'Rangpur'),
    ],
  );
  const zoneA = SalesZone(
    id: 1,
    zoneName: 'Zone A',
    districts: [
      ZoneDistrict(id: 3, name: 'Gazipur'),
      ZoneDistrict(id: 10, name: 'Mymensingh'),
    ],
  );
  const zoneG = SalesZone(
    id: 7,
    zoneName: 'Zone G',
    districts: [ZoneDistrict(id: 63, name: 'Narail')],
  );
  const master = [zoneC, zoneG, zoneA];

  group('ZoneScope.fromZones', () {
    test('accumulates every assigned zone rather than taking one', () {
      final scope = ZoneScope.fromZones([3, 1], master);

      expect(scope.zoneIds, {3, 1});
      expect(scope.zoneNames, {'zone c', 'zone a'});
      expect(scope.label, 'Zone C · Zone A');
    });

    test('unions the districts of every assigned zone', () {
      final scope = ZoneScope.fromZones([3, 1], master);

      expect(
        scope.districtNames,
        {'bogura', 'rajshahi', 'rangpur', 'gazipur', 'mymensingh'},
      );
    });

    test('ignores zones the employee is not assigned to', () {
      final scope = ZoneScope.fromZones([3], master);

      expect(scope.zoneNames, {'zone c'});
      expect(scope.districtNames.contains('narail'), isFalse);
    });

    test('is empty when no id resolves against the master', () {
      final scope = ZoneScope.fromZones([99, 100], master);

      expect(scope.isEmpty, isTrue);
      // An empty scope must not narrow anything, or a stale id would blank
      // every list instead of falling back to unfiltered.
      expect(scope.matches(zoneId: 42, zoneName: 'Zone Z'), isTrue);
    });

    test('is empty for no assigned zones', () {
      expect(ZoneScope.fromZones(const [], master).isEmpty, isTrue);
    });
  });

  group('ZoneScope.matches', () {
    final scope = ZoneScope.fromZones([1], master);

    test('keeps a row tagged with an assigned zone id', () {
      expect(scope.matches(zoneId: 1, zoneName: 'Anything'), isTrue);
    });

    // Zone ids are assigned independently per system, so a row from another
    // source can carry a different id for the same zone. The name is the join.
    test('keeps a row matched by zone name when its id differs', () {
      expect(scope.matches(zoneId: 901, zoneName: 'Zone A'), isTrue);
      expect(scope.matches(zoneId: null, zoneName: 'zone a'), isTrue);
    });

    // The reason filtering happens client-side: rows predating zone tagging
    // carry zone_id NULL and would vanish under a server-side zone_id filter.
    test('keeps an untagged row whose district belongs to the zone', () {
      expect(scope.matches(district: 'Gazipur'), isTrue);
      expect(scope.matches(zoneName: '', district: 'gazipur'), isTrue);
    });

    test('matches districts in both directions', () {
      expect(scope.matches(district: 'Gazipur Division'), isTrue);
      expect(scope.matches(district: 'Gazipur Sadar'), isTrue);
    });

    test('drops a row in neither the zone nor its districts', () {
      expect(scope.matches(zoneId: 3, zoneName: 'Zone C'), isFalse);
      expect(scope.matches(district: 'Narail'), isFalse);
    });

    test('drops a row with no zone and no district', () {
      expect(scope.matches(), isFalse);
      expect(scope.matches(zoneId: null, zoneName: null, district: null), isFalse);
    });

    test('keeps a union across several assigned zones', () {
      final multi = ZoneScope.fromZones([1, 3], master);

      expect(multi.matches(zoneName: 'Zone A'), isTrue);
      expect(multi.matches(zoneName: 'Zone C'), isTrue);
      expect(multi.matches(district: 'Bogura'), isTrue);
      expect(multi.matches(zoneName: 'Zone G'), isFalse);
    });
  });

  group('ZoneScope json round-trip', () {
    test('survives a cache round-trip', () {
      final scope = ZoneScope.fromZones([1, 3], master);
      final restored = ZoneScope.fromJson(scope.toJson());

      expect(restored.zoneIds, scope.zoneIds);
      expect(restored.zoneNames, scope.zoneNames);
      expect(restored.districtNames, scope.districtNames);
      expect(restored.label, scope.label);
      expect(restored.matches(district: 'Rajshahi'), isTrue);
    });
  });

  group('AuthUserProfile zoneIds', () {
    AuthUserProfile profileWith(Object? zoneId) =>
        AuthUserProfile.fromJson({'name': 'Test', 'zoneId': zoneId});

    // HRM returns a jsonb array. Parsing it as a scalar produced null, which
    // silently disabled every zone filter in the app.
    test('reads the jsonb array HRM actually returns', () {
      expect(profileWith([1, 2, 3]).zoneIds, [1, 2, 3]);
    });

    test('accepts a bare scalar and a string', () {
      expect(profileWith(3).zoneIds, [3]);
      expect(profileWith('3').zoneIds, [3]);
    });

    test('drops junk, negatives and duplicates but keeps order', () {
      expect(profileWith(['a', 0, -1, 4, 2, 4]).zoneIds, [4, 2]);
    });

    test('is empty for null, an empty list or an empty string', () {
      expect(profileWith(null).zoneIds, isEmpty);
      expect(profileWith(<int>[]).zoneIds, isEmpty);
      expect(profileWith('').zoneIds, isEmpty);
    });

    test('exposes the first zone through the legacy getter', () {
      expect(profileWith([3, 1]).zoneId, 3);
      expect(profileWith(<int>[]).zoneId, isNull);
    });
  });
}
