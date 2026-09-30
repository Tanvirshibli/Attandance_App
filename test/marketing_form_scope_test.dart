import 'package:employee_attendance/data/marketing_demo_masters.dart';
import 'package:employee_attendance/models/booking_form_data_models.dart';
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