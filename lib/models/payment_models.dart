import 'package:intl/intl.dart';

class EmployeeLoan {
  const EmployeeLoan({
    required this.id,
    required this.amount,
    required this.status,
    this.paidAmount,
    this.remainingAmount,
  });

  final int id;
  final double amount;
  final String status;
  final double? paidAmount;
  final double? remainingAmount;

  String get label => 'Loan #$id';

  factory EmployeeLoan.fromJson(Map<String, dynamic> json) {
    return EmployeeLoan(
      id: _toInt(json['id']),
      amount: _toDouble(json['amount'] ?? json['loanAmount']),
      status: (json['status'] ?? '').toString(),
      paidAmount: _toDoubleNullable(json['paidAmount'] ?? json['amountPaidSoFar']),
      remainingAmount: _toDoubleNullable(json['remainingAmount']),
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

class LoanPayment {
  const LoanPayment({
    required this.id,
    required this.amount,
    required this.date,
    required this.status,
    this.loanId,
  });

  final int id;
  final double amount;
  final String date;
  final String status;
  final int? loanId;

  String get formattedDate {
    final parsed = DateTime.tryParse(date);
    if (parsed == null) return date;
    return DateFormat('dd MMM yyyy').format(parsed);
  }

  factory LoanPayment.fromJson(Map<String, dynamic> json) {
    return LoanPayment(
      id: _toInt(json['id']),
      amount: _toDouble(json['amount']),
      date: (json['date'] ?? json['addDate'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      loanId: _toIntNullable(json['loanId']),
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

class PayrollRecord {
  const PayrollRecord({
    required this.id,
    required this.month,
    required this.netPay,
    required this.status,
    this.grossPay,
  });

  final int id;
  final String month;
  final double netPay;
  final String status;
  final double? grossPay;

  factory PayrollRecord.fromJson(Map<String, dynamic> json) {
    return PayrollRecord(
      id: _toInt(json['id']),
      month: (json['month'] ?? '').toString(),
      netPay: _toDouble(json['netPay'] ?? json['netSalary'] ?? json['amount']),
      status: (json['status'] ?? '').toString(),
      grossPay: _toDoubleNullable(json['grossPay'] ?? json['grossSalary']),
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
