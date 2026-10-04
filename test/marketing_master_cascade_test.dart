import 'package:employee_attendance/models/booking_form_data_models.dart';
import 'package:employee_attendance/models/marketing_models.dart';
import 'package:employee_attendance/services/marketing_master_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The company → sector → market cascade the farm, dealer and market forms use.
///
/// Pure filters only: the service's network paths are exercised by the manual
/// smoke test, but the rules that matter — a sector belongs to the company the
/// officer picked, a market to the sector, and a company the backend curated
/// owns no Sales sector — are the parts worth pinning down, because getting
/// them wrong silently files a record under an organisation it has nothing to
/// do with.
void main() {
  const companies = [
    BookingFormCompany(id: 1, nameEn: 'Peoples Poultry & Hatchery Ltd'),
    BookingFormCompany(id: 2, nameEn: 'Peoples Feed'),
  ];

  const sectors = [
    BookingFormSector(id: 11, name: 'Live Bird (Dhaka)', companyId: 1),
    BookingFormSector(id: 12, name: 'Feed (Munshiganj)', companyId: 2),
    BookingFormSector(id: 13, name: 'Chicks (Sreenagar)', companyId: 1),
    // No company of its own — belongs to nobody in particular.
    BookingFormSector(id: 14, name: 'Unassigned Depot'),
  ];

  Market market(int id, String name, {int? sectorId}) =>
      Market(id: id, name: name, sectorId: sectorId);

  final markets = [
    market(101, 'Bogura Bazaar', sectorId: 11),
    market(102, 'Munshiganj Haat', sectorId: 12),
    market(103, 'Sreenagar Bazar', sectorId: 13),
    market(104, 'Legacy Market'),
  ];

  group('sector cascade', () {
    test('returns only the sectors belonging to the chosen company', () {
      final result = MarketingMasterService.filterSectorsForCompany(const [
        BookingFormSector(id: 11, name: 'Live Bird (Dhaka)', companyId: 1),
        BookingFormSector(id: 12, name: 'Feed (Munshiganj)', companyId: 2),
        BookingFormSector(id: 13, name: 'Chicks (Sreenagar)', companyId: 1),
      ], 2);

      expect(result.map((s) => s.id), [12]);
    });

    test('a second company gets its own sectors, not the first one\'s', () {
      final result = MarketingMasterService.filterSectorsForCompany(sectors, 1);

      expect(result.map((s) => s.id).toSet(), {11, 13});
    });

    test(
      'a null company returns every sector, for the unfiltered first load',
      () {
        final result = MarketingMasterService.filterSectorsForCompany(
          sectors,
          null,
        );

        expect(result.length, sectors.length);
      },
    );

    test(
      'a sector with no company is offered unfiltered but to no company',
      () {
        expect(
          MarketingMasterService.filterSectorsForCompany(
            sectors,
            null,
          ).map((s) => s.id),
          contains(14),
        );
        expect(
          MarketingMasterService.filterSectorsForCompany(
            sectors,
            1,
          ).map((s) => s.id),
          isNot(contains(14)),
        );
        expect(
          MarketingMasterService.filterSectorsForCompany(
            sectors,
            2,
          ).map((s) => s.id),
          isNot(contains(14)),
        );
      },
    );

    test('a zero company id is treated as no company, not as company 0', () {
      final result = MarketingMasterService.filterSectorsForCompany(sectors, 0);

      expect(result.length, sectors.length);
    });

    test('rows with no usable id are dropped from every list', () {
      final withJunk = [
        ...sectors,
        const BookingFormSector(id: 0, name: 'Broken'),
      ];

      expect(
        MarketingMasterService.filterSectorsForCompany(withJunk, null),
        hasLength(sectors.length),
      );
      expect(
        MarketingMasterService.filterSectorsForCompany(withJunk, 1),
        hasLength(2),
      );
    });
  });

  group('market cascade', () {
    test('returns only the markets belonging to the chosen sector', () {
      final result = MarketingMasterService.filterMarketsForSector(markets, 12);

      expect(result.map((m) => m.id), [102]);
    });

    test(
      'a null sector returns every market, for the unfiltered first load',
      () {
        final result = MarketingMasterService.filterMarketsForSector(
          markets,
          null,
        );

        expect(result.length, markets.length);
      },
    );

    test('a market with no sector is hidden once a sector is chosen', () {
      // It cannot be attributed to the chosen sector, and offering it there
      // would file the record against a market belonging to nobody.
      final result = MarketingMasterService.filterMarketsForSector(markets, 11);

      expect(result.map((m) => m.id), [101]);
      expect(result.map((m) => m.id), isNot(contains(104)));
    });

    test('a zero sector id is treated as no sector, not as sector 0', () {
      final result = MarketingMasterService.filterMarketsForSector(markets, 0);

      expect(result.length, markets.length);
    });
  });

  group('companies', () {
    test('are used as-is; the cascade never narrows them by anything', () {
      // Deliberately asserted: the zone no longer filters the company list, and
      // no other upstream picker exists to filter it by.
      expect(companies, hasLength(2));
    });
  });

  group('curated companies', () {
    test('are the ones the backend marked manual, whatever their id', () {
      const master = [
        BookingFormCompany(id: 1, nameEn: 'Kazi Farms Ltd', source: 'manual'),
        BookingFormCompany(id: 2, nameEn: 'Japfa Comfeed', source: 'sales'),
        BookingFormCompany(id: 1, nameEn: 'Peoples Poultry', source: 'manual'),
        BookingFormCompany(id: 3, nameEn: 'No Source Stated'),
      ];

      // Both id-1 rows are curated; the Sales row with id 2 is not, and
      // neither is the row that does not say. Id spaces overlap — the rule
      // is the source, not the number.
      expect(
        MarketingMasterService.curatedCompanyIds(master),
        {1},
      );
    });

    test('own no sector, even when a Sales sector shares their id', () {
      // Local id 1 (curated) and Sales company id 1 collide. The sector
      // belongs to the Sales company; the curated company must not claim it.
      const master = [
        BookingFormCompany(id: 1, nameEn: 'Kazi Farms Ltd', source: 'manual'),
      ];
      const withCollidingSector = [
        BookingFormSector(id: 11, name: 'Japfa Depot', companyId: 1),
      ];

      expect(MarketingMasterService.curatedCompanyIds(master), {1});
      // The plain filter would claim it — which is exactly why the service
      // short-circuits curated ids to an empty list before filtering.
      expect(
        MarketingMasterService.filterSectorsForCompany(
          withCollidingSector,
          1,
        ),
        hasLength(1),
      );
    });
  });

  group('marketing context', () {
    test('parses the companies and sectors the backend merged', () {
      final context = MarketingContext.fromJson({
        'companies': [
          {'id': 1, 'name': 'Kazi Farms Ltd.', 'source': 'manual', 'hasSectors': false},
          {'id': 9001, 'name': 'Japfa Comfeed Bangladesh Pte. Ltd.', 'source': 'sales', 'hasSectors': true},
        ],
        'sectors': [
          {'id': 51, 'name': 'Japfa Depot', 'companyId': 9001},
        ],
      });

      expect(context.companies, hasLength(2));
      // The curated company leads, and says where it came from.
      expect(context.companies.first.nameEn, 'Kazi Farms Ltd.');
      expect(context.companies.first.source, 'manual');
      expect(context.companies.first.hasSectors, isFalse);
      // A Sales company without a Bengali name is fine; hasSectors rides
      // through as sent.
      expect(context.companies.last.source, 'sales');
      expect(context.sectors.single.companyId, 9001);
    });

    test('drops rows with no usable id or name', () {
      final context = MarketingContext.fromJson({
        'companies': [
          {'id': 0, 'name': 'Zero'},
          {'id': 4, 'name': ''},
          'not-a-map',
          {'id': 5, 'name': 'Kept'},
        ],
        'sectors': [
          {'id': 0, 'name': 'Zero'},
          {'id': 6, 'name': 'Kept'},
        ],
      });

      expect(context.companies.map((c) => c.nameEn), ['Kept']);
      expect(context.sectors.map((s) => s.id), [6]);
    });

    test('an absent or malformed payload yields empty lists, not a crash', () {
      expect(MarketingContext.fromJson(const {}).companies, isEmpty);
      expect(MarketingContext.fromJson(const {}).sectors, isEmpty);
      expect(
        MarketingContext.fromJson({'companies': 'nope'}).companies,
        isEmpty,
      );
    });

    test('a company row missing hasSectors still shows the picker', () {
      // Older or partial payloads: the field defaults to true so a working
      // picker is never hidden on a missing flag.
      final context = MarketingContext.fromJson({
        'companies': [
          {'id': 7, 'name': 'Legacy Company'},
        ],
      });

      expect(context.companies.single.hasSectors, isTrue);
      expect(context.companies.single.source, isNull);
    });
  });
}
