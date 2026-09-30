import 'package:employee_attendance/data/marketing_demo_masters.dart';
import 'package:employee_attendance/models/booking_form_data_models.dart';
import 'package:employee_attendance/models/marketing_context.dart';
import 'package:employee_attendance/models/marketing_models.dart';
import 'package:employee_attendance/services/employee_marketing_scope_service.dart';
import 'package:employee_attendance/services/marketing_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the pure logic behind the v2.4.0 marketing form changes: phone
/// normalisation for the uniqueness check, and the scope object the read-only
/// fields render.
void main() {
  group('phone normalisation', () {
    test('treats the same number written three ways as one number', () {
      // A uniqueness check that compared raw strings would let one dealer's
      // phone be registered as +8801712…, 01712… and 01712-… separately.
      expect(
        MarketingService.samePhone('01712345678', '01712-345678'),
        isTrue,
      );
      expect(
        MarketingService.samePhone('+8801712345678', '01712345678'),
        isTrue,
      );
      expect(
        MarketingService.samePhone('008801712345678', '01712345678'),
        isTrue,
      );
      expect(
        MarketingService.samePhone('  01712345678 ', '01712345678'),
        isTrue,
      );
    });

    test('keeps genuinely different numbers apart', () {
      expect(MarketingService.samePhone('01712345678', '01712345679'), isFalse);
      // A short number must not collide with a longer one that contains it.
      expect(MarketingService.samePhone('1712', '01712345678'), isFalse);
    });

    test('treats an empty or missing phone as no match', () {
      expect(MarketingService.samePhone('', '01712345678'), isFalse);
      expect(MarketingService.samePhone(null, '01712345678'), isFalse);
      expect(MarketingService.samePhone('01712345678', null), isFalse);
      expect(MarketingService.samePhone(null, null), isFalse);
    });

    test('normalisePhone strips the country code and national trunk zero', () {
      expect(MarketingService.normalisePhone('+8801712345678'), '1712345678');
      expect(MarketingService.normalisePhone('01712345678'), '1712345678');
      expect(MarketingService.normalisePhone('(01712) 345-678'), '1712345678');
      // A number with no leading zero or country code is left alone.
      expect(MarketingService.normalisePhone('1712345678'), '1712345678');
    });
  });

  group('EmployeeMarketingScope', () {
    test('an empty scope reports no zone and is not complete', () {
      const scope = EmployeeMarketingScope.empty();
      expect(scope.hasZone, isFalse);
      expect(scope.isComplete, isFalse);
      expect(scope.zone, isNull);
      expect(scope.company, isNull);
      expect(scope.sector, isNull);
      expect(scope.market, isNull);
    });

    test('a fully resolved scope reports complete', () {
      const scope = EmployeeMarketingScope(
        zone: MarketingDemoNamed(id: 3, name: 'Dhaka South'),
        company: BookingFormCompany(id: 12, nameEn: 'Peoples Poultry'),
        sector: BookingFormSector(id: 44, name: 'Savar'),
      );
      expect(scope.hasZone, isTrue);
      // Market is still null, so this is deliberately not complete.
      expect(scope.isComplete, isFalse);
    });

    test('round-trips through json by id and name', () {
      const original = EmployeeMarketingScope(
        zone: MarketingDemoNamed(id: 3, name: 'Dhaka South'),
        company: BookingFormCompany(id: 12, nameEn: 'Peoples Poultry'),
        sector: BookingFormSector(id: 44, name: 'Savar'),
      );

      final restored = EmployeeMarketingScope.fromJson(original.toJson());

      expect(restored.zone?.id, 3);
      expect(restored.zone?.name, 'Dhaka South');
      expect(restored.company?.id, 12);
      expect(restored.company?.displayName, 'Peoples Poultry');
      expect(restored.sector?.id, 44);
      expect(restored.sector?.name, 'Savar');
    });

    test('a partial json yields nulls rather than throwing', () {
      // Missing ids must not become a scope member with a zero id, which would
      // be written into the payload and rejected by the API.
      final restored = EmployeeMarketingScope.fromJson(const {});
      expect(restored.zone, isNull);
      expect(restored.company, isNull);
      expect(restored.sector, isNull);
    });
  });

  group('MarketingContext', () {
    Map<String, dynamic> payload({
      bool withCompany = true,
      bool withSector = true,
      bool withMarkets = true,
    }) {
      return {
        'zone': {'id': 4, 'name': 'Zone B'},
        'company': withCompany
            ? {'id': 12, 'name': 'Peoples Poultry & Hatchery Ltd'}
            : null,
        'sector': withSector
            ? {'id': 44, 'name': 'Dhaka South', 'companyId': 12}
            : null,
        'sectors': withSector
            ? [
                {
                  'id': 44,
                  'name': 'Dhaka South',
                  'companyId': 12,
                  'companyName': 'Peoples Poultry & Hatchery Ltd',
                }
              ]
            : <dynamic>[],
        'markets': withMarkets
            ? [
                {
                  'id': 9,
                  'name': 'Rajshahi city market',
                  'district': 'Rajshahi',
                  'companyName': 'Peoples Poultry & Hatchery Ltd',
                  'sectorName': 'Dhaka South',
                }
              ]
            : <dynamic>[],
      };
    }

    test('parses the whole resolved context', () {
      final context = MarketingContext.fromJson(payload());

      expect(context.hasZone, isTrue);
      expect(context.zone!.id, 4);
      expect(context.zone!.name, 'Zone B');
      // The company arrives through the sector's real relation, so the form no
      // longer has to guess it from a name.
      expect(context.company!.id, 12);
      expect(context.sector!.name, 'Dhaka South');
      expect(context.sectors, hasLength(1));
      expect(context.markets, hasLength(1));
      expect(context.markets.first.name, 'Rajshahi city market');
    });

    test('a zone with no company is distinguishable from an empty scope', () {
      // An officer whose zone is set but whose sector has no company needs the
      // admin to fix the sector — not the whole profile.
      final context = MarketingContext.fromJson(
        payload(withCompany: false, withSector: false),
      );

      expect(context.hasZone, isTrue);
      expect(context.company, isNull);
      expect(context.hasZoneWithoutCompany, isTrue);
    });

    test('a null payload degrades to an empty context', () {
      final context = MarketingContext.fromJson(null);
      expect(context.hasZone, isFalse);
      expect(context.company, isNull);
      expect(context.markets, isEmpty);
    });

    test('missing keys do not become zero-id members', () {
      // A zero id written into the payload would be rejected by the API, so an
      // absent key has to become null.
      final context = MarketingContext.fromJson(const {});
      expect(context.zone, isNull);
      expect(context.company, isNull);
      expect(context.sector, isNull);
      expect(context.sectors, isEmpty);
      expect(context.markets, isEmpty);
    });
  });

  group('MarketingDealer', () {
    test('reads the proxy dealer payload', () {
      final dealer = MarketingDealer.fromJson(const {
        'sourceId': 19,
        'name': 'Al-Modina Poultry',
        'code': 'DLR250019',
        'contactPerson': 'Md. Rahim Uddin',
        'phone': '01712345678',
        'address': 'Nagarbari, Savar',
        'zoneName': 'Zone A',
        'dealerGroup': 'egg',
      });

      expect(dealer.sourceId, 19);
      expect(dealer.displayName, 'Al-Modina Poultry');
      expect(dealer.subtitle, contains('DLR250019'));
      expect(dealer.subtitle, contains('01712345678'));
    });

    test('tolerates a dealer carrying no optional fields', () {
      // Egg dealers in the Sales payload have no addressBn/shippingAddress, and
      // any field may be null — none of it may throw.
      final dealer = MarketingDealer.fromJson(const {
        'sourceId': 27,
        'name': 'Delta Poultry',
      });

      expect(dealer.code, isNull);
      expect(dealer.phone, isNull);
      expect(dealer.zoneName, isNull);
      // An empty subtitle keeps the option tile on one line rather than ' · '.
      expect(dealer.subtitle, isNot(contains('·')));
      expect(dealer.searchText, contains('delta poultry'));
    });

    test('falls back to a readable name when the dealer has none', () {
      final dealer = MarketingDealer.fromJson(const {'sourceId': 5, 'name': ''});
      expect(dealer.displayName, 'Dealer #5');
    });
  });

  group('phone uniqueness pools', () {
    // Mirrors the server: a farm and a dealer may share a number, two farms may
    // not. The client has to scope its warning the same way or it would block a
    // save the database accepts.
    final farm = Party.fromJson(const {
      'id': 1,
      'partyType': 'farm',
      'name': 'A Farm',
      'phone': '01712345678',
    });
    final dealer = Party.fromJson(const {
      'id': 2,
      'partyType': 'dealer',
      'name': 'A Dealer',
      'phone': '01712345678',
    });

    test('a farm phone clashes only with another farm', () {
      expect(farm.isFarm, isTrue);
      expect(dealer.isFarm, isFalse);
    });

    test('the same number in different pools is not a clash', () {
      bool clashes(Party typed, Party other, {required bool typedIsFarm}) {
        if (!MarketingService.samePhone(other.phone, typed.phone)) return false;
        return other.isFarm == typedIsFarm;
      }

      expect(clashes(farm, dealer, typedIsFarm: true), isFalse);
      expect(clashes(dealer, farm, typedIsFarm: false), isFalse);
      expect(clashes(farm, farm, typedIsFarm: true), isTrue);
      expect(clashes(dealer, dealer, typedIsFarm: false), isTrue);
    });
  });

  group('Market model', () {
    test('reads phone from the wire payload', () {
      final market = Market.fromJson(const {
        'id': 7,
        'name': 'Savar Market',
        'phone': '01712345678',
      });
      expect(market.phone, '01712345678');
    });

    test('treats an absent phone as null', () {
      final market = Market.fromJson(const {'id': 7, 'name': 'Savar Market'});
      expect(market.phone, isNull);
    });
  });
}