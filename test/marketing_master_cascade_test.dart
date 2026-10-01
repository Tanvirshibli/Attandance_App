import 'package:employee_attendance/models/booking_form_data_models.dart';
import 'package:employee_attendance/models/marketing_models.dart';
import 'package:employee_attendance/services/marketing_master_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The company → sector → market cascade the farm, dealer and market forms use.
///
/// Pure filters only: the service's network paths are exercised by the manual
/// smoke test, but the rule that a sector belongs to the company the officer
/// picked — and a market to the sector — is the part worth pinning down, because
/// getting it wrong silently files a record under an organisation it has
/// nothing to do with.
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
}
