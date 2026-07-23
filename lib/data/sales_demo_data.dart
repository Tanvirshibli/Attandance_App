import '../models/sales_models.dart';

/// In-memory demo sales data. Postings can be appended from [PostSaleScreen].
/// Reporting demo is only used when [AppConfig.useSalesDemoData] is true.
class SalesDemoData {
  SalesDemoData._();

  static final List<SalePosting> _postings = [
    SalePosting(
      id: 1001,
      employeeId: 0,
      saleDate: _daysAgo(2),
      amount: 18500,
      customerName: 'Green Valley Outlet',
      productName: 'Layer Feed 50kg',
      quantity: 40,
      notes: 'Monthly restock',
      status: 'approved',
    ),
    SalePosting(
      id: 1002,
      employeeId: 0,
      saleDate: _daysAgo(5),
      amount: 9200,
      customerName: 'Sunrise Agro Store',
      productName: 'Broiler Starter',
      quantity: 20,
      status: 'submitted',
    ),
    SalePosting(
      id: 1003,
      employeeId: 0,
      saleDate: _daysAgo(9),
      amount: 27400,
      customerName: 'City Farm Depot',
      productName: 'Premix Vitamin Pack',
      quantity: 12,
      notes: 'Promo bundle',
      status: 'approved',
    ),
  ];

  static int _nextId = 1100;

  static String _daysAgo(int days) {
    final d = DateTime.now().subtract(Duration(days: days));
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static SalesPersonSalesData personSales({
    required int employeeId,
    required DateTime fromDate,
    required DateTime toDate,
  }) {
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

    final feedSummary = SalesModuleSummary.fromJson({
      'total_orders': 3,
      'total_returns': 0,
      'total_details': 3,
      'total_products': 2,
      'total_dealers': 2,
      'total_sectors': 1,
      'gross_qty': 70,
      'return_qty': 0,
      'net_qty': 70,
      'delivered_qty': 70,
      'pcs_qty': 0,
      'scale_weight': 0,
      'gross_sales': 55100,
      'sales_return': 0,
      'net_sales': 55100,
      'invoice_net_total': 55100,
    });

    final empty = SalesModuleSummary.fromJson(const {});

    return SalesPersonSalesData(
      employee: SalesPersonEmployee(
        inputId: employeeId,
        employeeId: employeeId,
        employeeName: 'Demo Sales Person',
      ),
      fromDate: fmt(fromDate),
      toDate: fmt(toDate),
      overall: SalesOverallSummary.fromJson({
        'total_orders': 3,
        'total_returns': 0,
        'total_details': 3,
        'gross_sales': 55100,
        'sales_return': 0,
        'net_sales': 55100,
        'invoice_net_total': 55100,
        'quantity_by_unit': [
          {
            'unit_id': 1,
            'unit_name': 'kg',
            'gross_qty': 70,
            'return_qty': 0,
            'net_qty': 70,
          },
        ],
      }),
      modules: [
        SalesModuleBlock(
          key: 'egg',
          label: 'Egg',
          summary: empty,
          products: const [],
          dealers: const [],
          sectors: const [],
          details: const [],
        ),
        SalesModuleBlock(
          key: 'feed',
          label: 'Feed',
          summary: feedSummary,
          products: [
            SalesProductRow.fromJson({
              'id': 1,
              'name': 'Layer Feed 50kg',
              'total_orders': 2,
              'total_returns': 0,
              'gross_qty': 50,
              'return_qty': 0,
              'net_qty': 50,
              'delivered_qty': 50,
              'pcs_qty': 0,
              'scale_weight': 0,
              'gross_amount': 27700,
              'return_amount': 0,
              'net_amount': 27700,
              'unit_name': 'Bag',
            }),
            SalesProductRow.fromJson({
              'id': 2,
              'name': 'Broiler Starter',
              'total_orders': 1,
              'total_returns': 0,
              'gross_qty': 20,
              'return_qty': 0,
              'net_qty': 20,
              'delivered_qty': 20,
              'pcs_qty': 0,
              'scale_weight': 0,
              'gross_amount': 27400,
              'return_amount': 0,
              'net_amount': 27400,
              'unit_name': 'Bag',
            }),
          ],
          dealers: [
            SalesPartyRow.fromJson({
              'id': 10,
              'name': 'Green Valley Outlet',
              'total_orders': 2,
              'total_returns': 0,
              'gross_qty': 50,
              'return_qty': 0,
              'net_qty': 50,
              'delivered_qty': 50,
              'pcs_qty': 0,
              'scale_weight': 0,
              'gross_amount': 27700,
              'return_amount': 0,
              'net_amount': 27700,
            }),
          ],
          sectors: [
            SalesPartyRow.fromJson({
              'id': 1,
              'name': 'North Zone',
              'total_orders': 3,
              'total_returns': 0,
              'gross_qty': 70,
              'return_qty': 0,
              'net_qty': 70,
              'delivered_qty': 70,
              'pcs_qty': 0,
              'scale_weight': 0,
              'gross_amount': 55100,
              'return_amount': 0,
              'net_amount': 55100,
            }),
          ],
          details: [
            SalesDetailLine.fromJson({
              'module': 'feed',
              'order_id': 1001,
              'reference_no': 'SO-DEMO-1',
              'detail_id': 1,
              'type': 'order',
              'invoice_date': _daysAgo(2),
              'status': 'approved',
              'qty': 40,
              'line_amount': 18500,
              'dealer_name': 'Green Valley Outlet',
              'product_name': 'Layer Feed 50kg',
              'unit_name': 'Bag',
            }),
          ],
        ),
        for (final def in const [
          ('fertilizer', 'Fertilizer'),
          ('chicks', 'Chicks'),
          ('liveBird', 'Live Bird'),
          ('cullBird', 'Cull Bird'),
        ])
          SalesModuleBlock(
            key: def.$1,
            label: def.$2,
            summary: empty,
            products: const [],
            dealers: const [],
            sectors: const [],
            details: const [],
          ),
      ],
    );
  }

  static SalePosting addPosting(CreateSaleRequest request) {
    final posting = SalePosting(
      id: _nextId++,
      employeeId: request.employeeId,
      saleDate: request.saleDate,
      amount: request.amount,
      customerName: request.customerName,
      productName: request.productName,
      quantity: request.quantity,
      notes: request.notes,
      status: 'submitted',
    );
    _postings.insert(0, posting);
    return posting;
  }
}
