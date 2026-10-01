// sales_service re-exports the booking form-data models, so BookingFormProductPrice
// and SalesProductCatalog both come in through this one import.
import 'package:employee_attendance/services/sales_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The *Add Items* section of Booking Post is entered in **bags**, but
/// `POST /api/booking-person-books` stores `details[].qty` as **kg** verbatim
/// and reports divide by the product's `sizeOrWeight` to show bags again.
///
/// These tests pin the conversion and, more importantly, its failure modes: a
/// product with no bag size on file must keep working as kg rather than
/// silently booking zero or throwing.
void main() {
  BookingFormProductPrice product({
    double? sizeOrWeight,
    int? unitId,
  }) {
    return BookingFormProductPrice(
      productId: 137,
      productName: 'Broiler Starter Grower',
      tradePrice: 100,
      sizeOrWeight: sizeOrWeight,
      unitId: unitId,
    );
  }

  group('bagsToKg — the conversion', () {
    test('multiplies a bag count by the kg per bag', () {
      expect(product(sizeOrWeight: 25).bagsToKg(4), 100);
    });

    test('handles a fractional bag count', () {
      expect(product(sizeOrWeight: 25).bagsToKg(2.5), 62.5);
    });

    test('handles a 50 kg bag, which is the other common feed packaging', () {
      expect(product(sizeOrWeight: 50).bagsToKg(3), 150);
    });

    test('zero bags stays zero', () {
      expect(product(sizeOrWeight: 25).bagsToKg(0), 0);
    });
  });

  group('bagsToKg — degrading safely when the bag size is unknown', () {
    // The dangerous failure is a zero here: it would book a real order as 0 kg
    // and look like it worked. The typed number must pass through instead.
    test('a null bag size passes the typed number through unchanged', () {
      expect(product().bagsToKg(4), 4);
    });

    test('a zero bag size passes through rather than booking zero', () {
      expect(product(sizeOrWeight: 0).bagsToKg(4), 4);
    });

    test('a negative bag size is not treated as known', () {
      // Defensive: the column is nullable decimal, but a junk value must not
      // invert the quantity.
      expect(product(sizeOrWeight: -5).bagSizeIsKnown, isFalse);
      expect(product(sizeOrWeight: -5).bagsToKg(4), 4);
    });
  });

  group('bagSizeIsKnown', () {
    test('true only for a positive bag size', () {
      expect(product(sizeOrWeight: 25).bagSizeIsKnown, isTrue);
      expect(product(sizeOrWeight: 0.5).bagSizeIsKnown, isTrue);
    });

    test('false for null, zero and negative', () {
      expect(product().bagSizeIsKnown, isFalse);
      expect(product(sizeOrWeight: 0).bagSizeIsKnown, isFalse);
      expect(product(sizeOrWeight: -1).bagSizeIsKnown, isFalse);
    });
  });

  group('qtyUnitLabel', () {
    test('reads Bag once the conversion is available', () {
      expect(product(sizeOrWeight: 25).qtyUnitLabel, 'Bag');
    });

    // The label must never promise a conversion the app cannot make.
    test('falls back to Kg when there is no bag size', () {
      expect(product().qtyUnitLabel, 'Kg');
      expect(product(sizeOrWeight: 0).qtyUnitLabel, 'Kg');
    });
  });

  group('fromJson — sizeOrWeight parsing', () {
    // `products."sizeOrWeight"` is a decimal and the Laravel `Product` model
    // declares no $casts, so it serialises as the STRING "50.00" at least as
    // often as the number 50. Reading only the numeric form would silently
    // yield null and drop the app back to kg.
    test('parses the string decimal form', () {
      final parsed = BookingFormProductPrice.fromJson({
        'productId': 137,
        'productName': 'Broiler Starter Grower',
        'tradePrice': 100,
        'sizeOrWeight': '50.00',
        'unitId': 1,
      });

      expect(parsed.sizeOrWeight, 50);
      expect(parsed.bagsToKg(2), 100);
      expect(parsed.unitId, 1);
    });

    test('parses the numeric form', () {
      final parsed = BookingFormProductPrice.fromJson({
        'productId': 137,
        'productName': 'Broiler Starter Grower',
        'tradePrice': 100,
        'sizeOrWeight': 25,
      });

      expect(parsed.sizeOrWeight, 25);
    });

    test('parses the snake_case alias', () {
      final parsed = BookingFormProductPrice.fromJson({
        'productId': 137,
        'productName': 'Broiler Starter Grower',
        'tradePrice': 100,
        'size_or_weight': 20,
      });

      expect(parsed.sizeOrWeight, 20);
    });

    test('leaves the size null when the key is absent', () {
      final parsed = BookingFormProductPrice.fromJson({
        'productId': 137,
        'productName': 'Broiler Starter Grower',
        'tradePrice': 100,
      });

      expect(parsed.sizeOrWeight, isNull);
      expect(parsed.bagSizeIsKnown, isFalse);
      expect(parsed.qtyUnitLabel, 'Kg');
      // And the quantity still survives, rather than becoming 0.
      expect(parsed.bagsToKg(4), 4);
    });

    test('a non-numeric size does not throw', () {
      final parsed = BookingFormProductPrice.fromJson({
        'productId': 137,
        'productName': 'Broiler Starter Grower',
        'tradePrice': 100,
        'sizeOrWeight': 'not-a-number',
      });

      expect(parsed.sizeOrWeight, isNull);
      expect(parsed.bagSizeIsKnown, isFalse);
    });
  });

  group('withBagSize', () {
    test('returns a copy carrying the resolved size and unit', () {
      final original = product();
      final resolved = original.withBagSize(sizeOrWeight: 25, unitId: 1);

      expect(resolved.sizeOrWeight, 25);
      expect(resolved.unitId, 1);
      expect(original.sizeOrWeight, isNull, reason: 'must not mutate');
    });

    test('keeps existing values when the catalog had nothing', () {
      final resolved =
          product(sizeOrWeight: 25, unitId: 1).withBagSize();

      expect(resolved.sizeOrWeight, 25);
      expect(resolved.unitId, 1);
    });

    test('preserves the rest of the product identity', () {
      final resolved = product().withBagSize(sizeOrWeight: 25, unitId: 1);

      expect(resolved.productId, 137);
      expect(resolved.productName, 'Broiler Starter Grower');
      expect(resolved.tradePrice, 100);
    });
  });

  group('SalesProductCatalog', () {
    test('indexes the API payload by product id', () {
      final catalog = SalesProductCatalog.fromApiList([
        {
          'id': 137,
          'productName': 'Broiler Starter Grower',
          'sizeOrWeight': '25.00',
          'shortName': 'BSG',
          'unitId': 1,
        },
        {'id': 138, 'productName': 'Layer Grower', 'sizeOrWeight': 50.0},
      ]);

      expect(catalog.length, 2);
      expect(catalog.sizeOrWeightFor(137), 25);
      expect(catalog.unitIdFor(137), 1);
      expect(catalog.sizeOrWeightFor(138), 50);
    });

    test('an unknown product yields nulls, not zeroes', () {
      final catalog = SalesProductCatalog.fromApiList([
        {'id': 137, 'sizeOrWeight': '25.00'},
      ]);

      expect(catalog.sizeOrWeightFor(999), isNull);
      expect(catalog.unitIdFor(999), isNull);
    });

    test('drops entries with neither a size nor a unit', () {
      // Keeps `length` meaningful: a row that says nothing about the product is
      // noise, not a catalog hit.
      final catalog = SalesProductCatalog.fromApiList([
        {'id': 137, 'sizeOrWeight': '25.00'},
        {'id': 138, 'productName': 'No size recorded'},
      ]);

      expect(catalog.length, 1);
      expect(catalog.sizeOrWeightFor(138), isNull);
    });

    test('ignores rows that are not objects or have no usable id', () {
      final catalog = SalesProductCatalog.fromApiList([
        'garbage',
        42,
        {'productName': 'No id'},
        {'id': 0, 'sizeOrWeight': 25},
        {'id': 137, 'sizeOrWeight': 25},
      ]);

      expect(catalog.length, 1);
      expect(catalog.sizeOrWeightFor(137), 25);
    });

    test('an empty payload produces an empty catalog', () {
      final catalog = SalesProductCatalog.fromApiList([]);

      expect(catalog.length, 0);
      expect(catalog.sizeOrWeightFor(137), isNull);
    });

    test('a rejected size is null rather than NaN', () {
      final catalog = SalesProductCatalog.fromApiList([
        {'id': 137, 'sizeOrWeight': 'abc'},
        {'id': 138, 'sizeOrWeight': null},
      ]);

      expect(catalog.length, 0);
      expect(catalog.sizeOrWeightFor(137), isNull);
    });
  });

  group('end-to-end: typing bags through to the wire', () {
    test('4 bags of a 25 kg product records 100 kg and totals on that kg', () {
      final line = product(sizeOrWeight: 25, unitId: 1);

      expect(line.bagsToKg(4), 100);
      // The server computes total = qty(kg) x price(per kg).
      expect(line.bagsToKg(4) * 100, 10000);
    });

    test('a product with no bag size keeps recording the typed number', () {
      final line = product();

      expect(line.bagsToKg(4), 4);
      expect(line.qtyUnitLabel, 'Kg');
    });
  });
}
