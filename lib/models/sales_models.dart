import 'package:intl/intl.dart';

class SalesOverview {
  const SalesOverview({
    required this.period,
    required this.targetAmount,
    required this.achievedAmount,
    required this.ordersCount,
    required this.revenue,
    required this.conversionRate,
    this.visitsCount,
  });

  final String period;
  final double targetAmount;
  final double achievedAmount;
  final int ordersCount;
  final double revenue;
  final double conversionRate;
  final int? visitsCount;

  double get progressRatio {
    if (targetAmount <= 0) return 0;
    return (achievedAmount / targetAmount).clamp(0.0, 1.5);
  }

  factory SalesOverview.fromJson(Map<String, dynamic> json) {
    return SalesOverview(
      period: (json['period'] ?? '').toString(),
      targetAmount: _toDouble(json['targetAmount'] ?? json['target']),
      achievedAmount: _toDouble(json['achievedAmount'] ?? json['achieved']),
      ordersCount: _toInt(json['ordersCount'] ?? json['orders']),
      revenue: _toDouble(json['revenue']),
      conversionRate: _toDouble(json['conversionRate'] ?? json['conversion']),
      visitsCount: _toIntNullable(json['visitsCount'] ?? json['visits']),
    );
  }

  static int _toInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static int? _toIntNullable(Object? v) {
    if (v == null) return null;
    return _toInt(v);
  }

  static double _toDouble(Object? v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }
}

class SalePosting {
  const SalePosting({
    required this.id,
    required this.employeeId,
    required this.saleDate,
    required this.amount,
    required this.customerName,
    this.productName,
    this.quantity,
    this.notes,
    this.status = 'submitted',
  });

  final int id;
  final int employeeId;
  final String saleDate;
  final double amount;
  final String customerName;
  final String? productName;
  final double? quantity;
  final String? notes;
  final String status;

  String get formattedDate {
    final parsed = DateTime.tryParse(saleDate);
    if (parsed == null) return saleDate;
    return DateFormat('dd MMM yyyy').format(parsed);
  }

  String get formattedAmount {
    final fmt = NumberFormat.currency(symbol: '৳', decimalDigits: 0);
    return fmt.format(amount);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'employeeId': employeeId,
        'saleDate': saleDate,
        'amount': amount,
        'customerName': customerName,
        if (productName != null) 'productName': productName,
        if (quantity != null) 'quantity': quantity,
        if (notes != null) 'notes': notes,
        'status': status,
      };

  factory SalePosting.fromJson(Map<String, dynamic> json) {
    return SalePosting(
      id: _toInt(json['id']),
      employeeId: _toInt(json['employeeId']),
      saleDate: (json['saleDate'] ?? json['date'] ?? '').toString(),
      amount: _toDouble(json['amount']),
      customerName:
          (json['customerName'] ?? json['outletName'] ?? 'Customer').toString(),
      productName: json['productName']?.toString(),
      quantity: _toDoubleNullable(json['quantity']),
      notes: json['notes']?.toString(),
      status: (json['status'] ?? 'submitted').toString(),
    );
  }

  static int _toInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double _toDouble(Object? v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double? _toDoubleNullable(Object? v) {
    if (v == null) return null;
    return _toDouble(v);
  }
}

class CreateSaleRequest {
  const CreateSaleRequest({
    required this.employeeId,
    required this.saleDate,
    required this.amount,
    required this.customerName,
    this.productName,
    this.quantity,
    this.notes,
  });

  final int employeeId;
  final String saleDate;
  final double amount;
  final String customerName;
  final String? productName;
  final double? quantity;
  final String? notes;

  Map<String, dynamic> toJson() => {
        'employeeId': employeeId,
        'saleDate': saleDate,
        'amount': amount,
        'customerName': customerName,
        if (productName != null && productName!.isNotEmpty)
          'productName': productName,
        if (quantity != null) 'quantity': quantity,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };
}

class SalesProfile {
  const SalesProfile({
    required this.isEligible,
    this.employeeName,
  });

  final bool isEligible;
  final String? employeeName;
}
