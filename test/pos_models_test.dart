import 'package:flutter_test/flutter_test.dart';

import 'package:employee_attendance/models/pos_models.dart';

void main() {
  final detailJson = {
    'company': {
      'id': 1,
      'nameEn': 'Peoples Poultry',
      'mobile': '01749-294031',
      'addressEn': 'Tangail, Dhaka, Bangladesh',
      'imageUrl': null,
    },
    'order': {
      'id': 6744,
      'feedId': 'CFO26116744',
      'invoiceDate': '2026-11-23',
      'dueDate': '2026-11-23',
      'status': 'approved',
      'deliveryAddress': 'Modhupur, Tangail',
    },
    'sector': {
      'id': 3,
      'name': 'Feed Mill',
      'description': 'Feed Mill SalesPoint(Sanebandha)',
      'sectorCode': 3,
    },
    'dealer': {
      'id': 12,
      'tradeName': 'Selim traders',
      'dealerCode': 'DLR262114',
      'zoneName': 'Zone A',
      'phone': '01864842424',
    },
    'salesPersonName': 'Sujat Ali',
    'driver': {'name': 'Mizan', 'phone': '01706-583330', 'address': 'Auto'},
    'items': [
      {
        'sn': 1,
        'productName': 'Comercial Feed Broiler Starter',
        'shortName': '101 Broiler Starter',
        'unit': 'Bag',
        'bagQty': 2,
        'qty': 100,
        'salePrice': 3251.5,
        'tradePrice': 3200,
        'amount': 6503.0,
      },
      {
        'sn': 2,
        'productName': 'Comercial Feed Broiler Grower',
        'shortName': '102 Broiler Grower',
        'unit': 'Bag',
        'bagQty': 12.5,
        'qty': 600,
        'salePrice': 3251.5,
        'tradePrice': 3200,
        'amount': 40643.75,
      },
    ],
    'totals': {
      'subTotal': 47146.75,
      'discount': 0,
      'fDiscount': 0,
      'discountTotal': 0,
      'vatPercent': 0,
      'totalTax': 0,
      'othersCost': 0,
      'transportCost': 100,
      'depotCost': 0,
      'advanceAmount': 0,
      'totalAmount': 55250,
      'dueAmount': 55250,
      'returnAmount': 0,
      'netAmount': 55250,
      'totalBagQuantity': 14.5,
      'totalQuantity': 700,
      'amountInWords': 'fifty-five thousand two hundred fifty taka only',
    },
  };

  test('parses the POS order payload the sales API returns', () {
    final order = PosOrderDetail.fromJson(detailJson);

    expect(order.id, 6744);
    expect(order.feedId, 'CFO26116744');
    expect(order.status, 'approved');
    expect(order.invoiceDateValue, DateTime(2026, 11, 23));
    expect(order.company.nameEn, 'Peoples Poultry');
    expect(order.sector?.label, 'Feed Mill (3)');
    expect(order.salesPersonName, 'Sujat Ali');
    expect(order.items, hasLength(2));
    expect(order.totals.totalAmount, 55250);
    expect(order.totals.amountInWords,
        'fifty-five thousand two hundred fifty taka only');
  });

  test('dealer label matches the web POS dealer line', () {
    final order = PosOrderDetail.fromJson(detailJson);
    expect(order.dealer?.displayName, 'Selim traders (DLR262114) Zone A');
  });

  test('receipt labels use the same quantity format as the web receipt', () {
    final order = PosOrderDetail.fromJson(detailJson);

    expect(order.items.first.quantityLabel, '2 Bag (100 Kg)');
    expect(order.items.last.quantityLabel, '12.5 Bag (600 Kg)');
    expect(order.items.last.displayName, '102 Broiler Grower');
  });

  test('order summary parses list rows', () {
    final summary = PosOrderSummary.fromJson({
      'id': 6744,
      'feedId': 'CFO26116744',
      'status': 'approved',
      'invoiceDate': '2026-11-23',
      'dueDate': '2026-11-23',
      'salesPersonName': 'Sujat Ali',
      'sector': {'id': 3, 'name': 'Feed Mill', 'sectorCode': 3},
      'dealer': {'tradeName': 'Selim traders', 'dealerCode': 'DLR262114'},
      'items': detailJson['items'],
      'totalQuantity': 700,
      'totalBagQuantity': 14.5,
      'totalAmount': 55250,
      'dueAmount': 55250,
    });

    expect(summary.salesDetailsLabel.split('\n').first,
        '1. Comercial Feed Broiler Starter: 2 Bag (100 Kg) * 3251.5 /-');
    expect(summary.totalBagQuantity, 14.5);
  });

  test('category tree parses nested nodes', () {
    final category = PosCategory.fromJson({
      'id': 5,
      'name': 'Feed',
      'subCategories': [
        {
          'id': 7,
          'name': 'Broiler',
          'childCategories': [
            {'id': 21, 'name': 'Starter'},
          ],
        },
      ],
    });

    expect(category.subCategories.single.childCategories.single.name,
        'Starter');
  });

  test('number formatting mirrors JavaScript template output', () {
    expect(formatPosNumber(2.0), '2');
    expect(formatPosNumber(12.5), '12.5');
    expect(formatPosNumber(0), '0');
  });
}
