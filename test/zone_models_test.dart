import 'dart:convert';
import 'dart:io';

import 'package:employee_attendance/models/dealer_list_models.dart';
import 'package:employee_attendance/models/zone_models.dart';
import 'package:employee_attendance/models/zone_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, dynamic> fixture;

  setUpAll(() {
    final file = File('test/fixtures/get_zone.json');
    fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  });

  group('SalesZone.listFrom', () {
    test('parses the get-zone envelope', () {
      final zones = SalesZone.listFrom(fixture);

      expect(zones, hasLength(3));
      expect(zones.first.id, 3);
      expect(zones.first.zoneName, 'Zone C');
      expect(zones.first.zonalInCharge, 'Md.Monowar Hossen-Sr.Manager');
      expect(zones.first.note, 'Ok');
    });

    test('keeps each district id and name', () {
      final zoneC = SalesZone.listFrom(fixture).first;

      expect(zoneC.districts, hasLength(3));
      expect(zoneC.districts.first.id, 18);
      expect(zoneC.districts.first.name, 'Bogura');
    });

    test('represents a null zonalInCharge as null, not "null"', () {
      final zoneG =
          SalesZone.listFrom(fixture).firstWhere((z) => z.id == 7);

      expect(zoneG.zonalInCharge, isNull);
    });

    test('drops rows with no usable id or name', () {
      final zones = SalesZone.listFrom({
        'data': [
          {'id': 1, 'zoneName': 'Zone A', 'districts': []},
          {'id': 0, 'zoneName': 'Broken'},
          {'id': 2, 'zoneName': ''},
          {'id': 3},
          'not an object',
        ],
      });

      expect(zones.map((z) => z.id), [1]);
    });

    test('drops districts with no id or name', () {
      final zones = SalesZone.listFrom({
        'data': [
          {
            'id': 1,
            'zoneName': 'Zone A',
            'districts': [
              {'id': 3, 'name': 'Gazipur'},
              {'id': 0, 'name': 'Nope'},
              {'id': 5, 'name': ''},
            ],
          },
        ],
      });

      expect(zones.first.districts.map((d) => d.name), ['Gazipur']);
    });

    test('is empty when the payload carries no list', () {
      expect(SalesZone.listFrom(const {}), isEmpty);
      expect(SalesZone.listFrom({'data': 'nope'}), isEmpty);
    });
  });

  group('ZoneScope.fromZones against the live fixture', () {
    test('resolves a multi-zone employee', () {
      final zones = SalesZone.listFrom(fixture);
      final scope = ZoneScope.fromZones([3, 1], zones);

      expect(scope.zoneNames, {'zone c', 'zone a'});
      expect(scope.label, 'Zone C · Zone A');
      expect(scope.matches(zoneName: 'Zone C'), isTrue);
      expect(scope.matches(district: 'Gazipur'), isTrue);
      expect(scope.matches(district: 'Narail'), isFalse);
    });
  });

  group('AllDealerLists.scopedTo', () {
    AllDealerLists listsOf(List<DealerListItem> egg) => AllDealerLists(
          egg: egg,
          feed: const [],
          fertilizer: const [],
          liveBird: const [],
          wastage: const [],
        );
    DealerListItem dealer(int id, String? zoneName) =>
        DealerListItem(id: id, tradeName: 'Dealer $id', zoneName: zoneName);

    test('keeps only dealers in an assigned zone', () {
      final scoped = listsOf([
        dealer(1, 'Zone A'),
        dealer(2, 'Zone C'),
        dealer(3, 'Zone G'),
      ]).scopedTo({'zone a', 'zone c'});

      expect(scoped.egg.map((d) => d.id), [1, 2]);
    });

    // The nested `zone.id` in the payload is not comparable across systems,
    // so a dealer from another source is matched on its name only.
    test('matches on the zone name, ignoring the id', () {
      final scoped = listsOf([
        dealer(1, '  Zone A  '),
        dealer(2, 'zone a'),
        dealer(3, 'Zone D'),
      ]).scopedTo({'zone a'});

      expect(scoped.egg.map((d) => d.id), [1, 2]);
    });

    test('keeps dealers with no zone, since they cannot be excluded', () {
      final scoped = listsOf([
        dealer(1, 'Zone A'),
        dealer(2, null),
      ]).scopedTo({'zone a'});

      expect(scoped.egg.map((d) => d.id), [1, 2]);
    });

    test('leaves every list untouched when no zones are assigned', () {
      final original = listsOf([dealer(1, 'Zone A'), dealer(2, 'Zone D')]);

      expect(original.scopedTo(const {}), same(original));
    });
  });
}
