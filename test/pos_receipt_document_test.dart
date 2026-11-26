import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:employee_attendance/models/pos_models.dart';
import 'package:employee_attendance/widgets/pos/pos_receipt_document.dart';

void main() {
  const order = PosOrderDetail(
    id: 6744,
    feedId: 'CFO26116744',
    status: 'approved',
    invoiceDate: '2026-11-23',
    dueDate: '2026-11-23',
    saleType: 'Cash',
    paymentStatus: 'Due',
    deliveryAddress: 'Modhupur, Tangail',
    company: PosCompany(
      nameEn: 'Peoples Poultry',
      mobile: '01749-294031',
      addressEn: 'Tangail, Dhaka, Bangladesh',
    ),
    sector: PosSector(
      id: 3,
      name: 'Feed Mill',
      description: 'Feed Mill SalesPoint(Sanebandha)',
      sectorCode: 3,
    ),
    dealer: PosDealer(
      tradeName: 'Selim traders',
      dealerCode: 'DLR262114',
      zoneName: 'Zone A',
      phone: '01864842424',
    ),
    salesPersonName: 'Sujat Ali',
    driver: PosDriver(name: 'Mizan', phone: '01706-583330', address: 'Auto'),
    items: [
      PosOrderItem(
        sn: 1,
        productName: 'Comercial Feed Broiler Starter',
        shortName: '101 Broiler Starter',
        bagQty: 2,
        qty: 100,
        salePrice: 3251.5,
        amount: 6503,
      ),
    ],
    totals: PosOrderTotals(
      subTotal: 6503,
      transportCost: 100,
      totalAmount: 6603,
      dueAmount: 6603,
      totalBagQuantity: 2,
      totalQuantity: 100,
      amountInWords: 'six thousand six hundred three taka only',
    ),
  );

  Future<void> pumpReceipt(WidgetTester tester, PosDocType docType) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PosReceiptDocument(order: order, docType: docType),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('challan receipt keeps the web field order', (tester) async {
    await pumpReceipt(tester, PosDocType.challan);

    expect(find.text('~~Delivery Challan ~~'), findsOneWidget);
    expect(find.text('Peoples Poultry'), findsOneWidget);
    expect(
        find.textContaining('Feed Mill SalesPoint(Sanebandha)',
            findRichText: true),
        findsOneWidget);
    expect(find.text('Selim traders (DLR262114) Zone A'), findsOneWidget);
    expect(find.text('01864842424'), findsOneWidget);
    expect(find.text('2 Bag (100 Kg)'), findsOneWidget);
    expect(find.text('2Bag (100Kg)'), findsOneWidget);
    expect(find.text('Sig: Sender'), findsOneWidget);
    expect(find.text('Sig: Receiver'), findsOneWidget);
    expect(find.text('Order #CFO26116744'), findsOneWidget);
    expect(find.text('Subtotal'), findsNothing);
  });

  testWidgets('invoice receipt carries no money either', (tester) async {
    await pumpReceipt(tester, PosDocType.invoice);

    expect(find.text('~~ Sales Invoice ~~'), findsOneWidget);
    // No totals block, no amount-in-words, no Price/Amount columns.
    expect(find.text('Subtotal'), findsNothing);
    expect(find.text('Total'), findsNothing);
    expect(find.text('Due'), findsNothing);
    expect(find.text('Advance'), findsNothing);
    expect(find.text('Price'), findsNothing);
    expect(find.text('Amount'), findsNothing);
    expect(find.textContaining('taka only'), findsNothing);
    expect(find.text('6503.00'), findsNothing);
    expect(find.text('6603.00/-'), findsNothing);
    expect(find.text('Sig: Sender'), findsNothing);
    expect(find.text('Total Quantity'), findsOneWidget);
    expect(find.text('Order #CFO26116744'), findsOneWidget);
  });

  testWidgets('receipt is 300 logical pixels wide (80 mm)', (tester) async {
    await pumpReceipt(tester, PosDocType.invoice);

    final size = tester.getSize(find.byType(PosReceiptDocument));
    expect(size.width, 300);
  });

  // The POS must never show money in the mobile app, on either document. This
  // scans every rendered string rather than checking known labels, so a future
  // price column or totals row cannot slip back in unnoticed.
  for (final docType in PosDocType.values) {
    testWidgets('${docType.name} document renders no money at all',
        (tester) async {
      await pumpReceipt(tester, docType);

      final rendered = <String>[
        ...tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data ?? ''),
        ...tester
            .widgetList<Text>(find.byType(Text))
            .expand((text) => text.textSpan == null
                ? const <String>[]
                : [text.textSpan!.toPlainText()]),
      ];

      // A money-ish render: "1234.00", "1234/-", "Rs 1234", "৳1234",
      // "taka only" (amount-in-words). Item names and quantities never match.
      final moneyPattern = RegExp(
        r'\d+\.\d{2}|/-|\btaka\b|৳|\bRs\.?\s?\d|Tk\.?\s?\d',
        caseSensitive: false,
      );

      for (final line in rendered) {
        expect(
          moneyPattern.hasMatch(line),
          isFalse,
          reason: '${docType.name} document must not render money: "$line"',
        );
      }

      // The delivery data the document exists for must still be there.
      expect(find.text('101 Broiler Starter'), findsOneWidget);
      expect(find.text('Total Quantity'), findsOneWidget);
      expect(find.text('Mizan'), findsOneWidget);
    });
  }
}
