import 'package:employee_attendance/data/marketing_demo_masters.dart';
import 'package:employee_attendance/models/booking_form_data_models.dart';
import 'package:employee_attendance/models/marketing_models.dart';
import 'package:employee_attendance/screens/marketing/farm_form_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rules behind the standalone Add Farm screen.
///
/// Pure logic only — no widget pumping and no network. The screen's own wiring
/// is covered by the manual emulator pass; what is worth pinning down here is the
/// set of decisions that would silently file a farm wrongly rather than crash:
/// which company it defaults to, how the search tells a real duplicate from a
/// substring hit, and the fact that a dealer sharing a farm's number is not a
/// conflict.
void main() {
  Party farm({
    int id = 1,
    String name = 'Rahim Poultry Farm',
    String? phone,
    String partyType = 'farm',
  }) =>
      Party(id: id, partyType: partyType, name: name, phone: phone);

  group('visit type', () {
    test('offers exactly the three farm kinds', () {
      expect(
        FarmFormScreen.visitTypes.map((t) => t.value),
        ['regular_farm', 'model_farm', 'other_farm'],
      );
    });

    test('defaults to a regular farm', () {
      expect(FarmFormScreen.defaultVisitType, 'regular_farm');
      expect(
        FarmFormScreen.visitTypes
            .any((t) => t.value == FarmFormScreen.defaultVisitType),
        isTrue,
      );
    });
  });

  group('farm type', () {
    test('offers exactly broiler, layer, color and all', () {
      expect(
        FarmFormScreen.farmTypes.map((t) => t.value),
        ['broiler', 'layer', 'color', 'all'],
      );
    });

    test('defaults to broiler', () {
      expect(
        FarmFormScreen.farmTypes
            .any((t) => t.value == FarmFormScreen.defaultFarmType),
        isTrue,
      );
    });
  });

  group('default company', () {
    const pphl = BookingFormCompany(
      id: 1,
      nameEn: 'Peoples Poultry & Hatchery Ltd',
    );
    const feed = BookingFormCompany(id: 2, nameEn: 'Peoples Feed');
    const rival = BookingFormCompany(id: 3, nameEn: 'Nourish Feed Ltd');

    test('preselects Peoples Poultry & Hatchery from a mixed list', () {
      expect(
        FarmFormScreen.defaultCompany([feed, rival, pphl])?.id,
        pphl.id,
      );
    });

    test('matches on a substring, so "&" vs "and" does not matter', () {
      const spelledOut = BookingFormCompany(
        id: 9,
        nameEn: 'Peoples Poultry and Hatchery Ltd',
      );
      expect(FarmFormScreen.defaultCompany([feed, spelledOut])?.id, 9);
    });

    test('falls back to the first company when nothing matches', () {
      expect(FarmFormScreen.defaultCompany([rival, feed])?.id, rival.id);
    });

    test('is null on an empty list, so submit blocks instead of guessing', () {
      expect(FarmFormScreen.defaultCompany(const []), isNull);
    });
  });

  group('search seeding', () {
    test('treats a long digit run as a phone', () {
      expect(FarmFormScreen.looksLikePhone('01712345678'), isTrue);
      expect(FarmFormScreen.looksLikePhone('+8801712345678'), isTrue);
      expect(FarmFormScreen.looksLikePhone('017-12345678'), isTrue);
    });

    test('treats words as a name, however digit-like they look', () {
      expect(FarmFormScreen.looksLikePhone('Rahim Poultry'), isFalse);
      expect(FarmFormScreen.looksLikePhone(''), isFalse);
      // Short enough that it cannot be a name either — but seeding it as a
      // phone is still the safer mistake.
      expect(FarmFormScreen.looksLikePhone('1712'), isFalse);
    });
  });

  group('farm match', () {
    test('a phone query picks the farm holding that number', () {
      final farms = [
        farm(id: 1, name: 'Alpha Farm', phone: '01711000001'),
        farm(id: 2, name: 'Beta Farm', phone: '01711000002'),
      ];
      expect(FarmFormScreen.exactFarmMatch(farms, '01711000002')?.id, 2);
    });

    test('a phone query ignores formatting differences', () {
      final farms = [farm(id: 1, phone: '01711000001')];
      expect(FarmFormScreen.exactFarmMatch(farms, '+8801711000001')?.id, 1);
    });

    test(
      'a phone query ignores a longer number that merely contains it',
      () {
        // The backend `q` is a substring LIKE, so typing 11 digits also returns
        // the 13-digit farm. Only an exact digit comparison can tell them apart.
        final farms = [farm(id: 1, name: 'Longer', phone: '017110000019')];
        final match = FarmFormScreen.exactFarmMatch(farms, '01711000001');
        expect(match?.id, 1, reason: 'falls back to the only candidate');
      },
    );

    test('a name query takes the closest spelling', () {
      final farms = [
        farm(id: 1, name: 'Rahim Poultry Farm'),
        farm(id: 2, name: 'Rahim Layer Farm'),
      ];
      expect(FarmFormScreen.exactFarmMatch(farms, 'Rahim')?.id, 1);
    });

    test('no candidates means no match', () {
      expect(FarmFormScreen.exactFarmMatch(const [], 'Rahim'), isNull);
      expect(FarmFormScreen.exactFarmMatch([farm()], '  '), isNull);
    });
  });

  group('phone uniqueness', () {
    test('flags a farm holding the number', () {
      final parties = [farm(id: 5, phone: '01711000009')];
      expect(
        FarmFormScreen.sameFarmPhone(parties, '01711000009')?.id,
        5,
      );
    });

    test('a dealer sharing the number is not a conflict', () {
      // The server scopes its unique index the same way, so warning here would
      // block a save the database accepts — the same person can run a farm and
      // trade as a dealer.
      final parties = [
        farm(id: 5, partyType: 'dealer', name: 'Al Amin Traders', phone: '01711000009'),
      ];
      expect(FarmFormScreen.sameFarmPhone(parties, '01711000009'), isNull);
    });

    test('a farmer is in the farm pool', () {
      final parties = [
        farm(id: 6, partyType: 'farmer', name: 'Karim', phone: '01711000007'),
      ];
      expect(FarmFormScreen.sameFarmPhone(parties, '01711000007')?.id, 6);
    });
  });

  group('product category filter', () {
    test('offers the whole catalogue before a category is chosen', () {
      expect(
        FarmFormScreen.productsInCategory(MarketingDemoMasters.products, null)
            .length,
        MarketingDemoMasters.products.length,
      );
    });

    test('narrows to the chosen category', () {
      const feed = MarketingDemoNamed(id: 21, name: 'Feed');
      final feedProducts = FarmFormScreen.productsInCategory(
        MarketingDemoMasters.products,
        feed,
      );

      expect(feedProducts, isNotEmpty);
      expect(feedProducts.every((p) => p.categoryId == feed.id), isTrue);
    });

    test('a category with nothing in it yields an empty list', () {
      const empty = MarketingDemoNamed(id: 999, name: 'Nothing');
      expect(
        FarmFormScreen.productsInCategory(MarketingDemoMasters.products, empty),
        isEmpty,
      );
    });
  });
}