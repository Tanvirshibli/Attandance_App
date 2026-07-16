import '../models/sales_models.dart';

/// In-memory demo sales data. Postings can be appended from [PostSaleScreen].
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
    SalePosting(
      id: 1004,
      employeeId: 0,
      saleDate: _daysAgo(14),
      amount: 15600,
      customerName: 'Northern Traders',
      productName: 'Layer Feed 50kg',
      quantity: 30,
      status: 'approved',
    ),
    SalePosting(
      id: 1005,
      employeeId: 0,
      saleDate: _daysAgo(21),
      amount: 6800,
      customerName: 'Lakeview Pet Shop',
      productName: 'Fish Meal',
      quantity: 8,
      status: 'rejected',
    ),
  ];

  static int _nextId = 1100;

  static String _daysAgo(int days) {
    final d = DateTime.now().subtract(Duration(days: days));
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static SalesOverview overviewForPeriod(String period) {
    switch (period) {
      case 'Last month':
        return const SalesOverview(
          period: 'Last month',
          targetAmount: 120000,
          achievedAmount: 108500,
          ordersCount: 18,
          revenue: 108500,
          conversionRate: 62.5,
          visitsCount: 29,
        );
      case 'Custom':
        return const SalesOverview(
          period: 'Custom',
          targetAmount: 250000,
          achievedAmount: 186400,
          ordersCount: 34,
          revenue: 186400,
          conversionRate: 58.0,
          visitsCount: 55,
        );
      case 'This month':
      default:
        return const SalesOverview(
          period: 'This month',
          targetAmount: 150000,
          achievedAmount: 77500,
          ordersCount: 12,
          revenue: 77500,
          conversionRate: 54.5,
          visitsCount: 22,
        );
    }
  }

  static List<SalePosting> postings({int? employeeId}) {
    return _postings
        .map(
          (p) => SalePosting(
            id: p.id,
            employeeId: employeeId ?? p.employeeId,
            saleDate: p.saleDate,
            amount: p.amount,
            customerName: p.customerName,
            productName: p.productName,
            quantity: p.quantity,
            notes: p.notes,
            status: p.status,
          ),
        )
        .toList();
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
