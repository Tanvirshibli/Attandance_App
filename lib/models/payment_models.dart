import 'package:intl/intl.dart';

double _toDouble(Object? v) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

double? _toDoubleNullable(Object? v) {
  if (v == null) return null;
  return _toDouble(v);
}

int _toInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

int? _toIntNullable(Object? v) {
  if (v == null) return null;
  return _toInt(v);
}

String _money(double value) {
  return NumberFormat.currency(symbol: '৳', decimalDigits: 0).format(value);
}

class EmployeeLoan {
  const EmployeeLoan({
    required this.id,
    required this.amount,
    required this.status,
    this.loanCode,
    this.loanType,
    this.paidAmount,
    this.remainingAmount,
    this.installmentAmount,
    this.installmentCount,
    this.deadlineDate,
    this.loanAddDate,
    this.interestPercentage,
    this.installmentType,
    this.note,
  });

  final int id;
  final double amount;
  final String status;
  final String? loanCode;
  final String? loanType;
  final double? paidAmount;
  final double? remainingAmount;
  final double? installmentAmount;
  final int? installmentCount;
  final String? deadlineDate;
  final String? loanAddDate;
  final double? interestPercentage;
  final String? installmentType;
  final String? note;

  String get label => loanCode?.isNotEmpty == true ? loanCode! : 'Loan #$id';

  String get formattedAmount => _money(amount);

  String get formattedRemaining =>
      _money(remainingAmount ?? (amount - (paidAmount ?? 0)));

  factory EmployeeLoan.fromJson(Map<String, dynamic> json) {
    final amount = _toDouble(json['amount'] ?? json['loanAmount']);
    final paid = _toDoubleNullable(
      json['paidAmount'] ?? json['amountPaidSoFar'],
    );
    final remaining = _toDoubleNullable(json['remainingAmount']) ??
        (paid != null ? (amount - paid).clamp(0, amount) : null);

    return EmployeeLoan(
      id: _toInt(json['id']),
      loanCode: json['loanId']?.toString(),
      amount: amount,
      status: (json['status'] ?? '').toString(),
      loanType: json['loanType']?.toString(),
      paidAmount: paid,
      remainingAmount: remaining,
      installmentAmount: _toDoubleNullable(json['installmentAmount']),
      installmentCount: _toIntNullable(json['installmentCount']),
      deadlineDate: json['deadlineDate']?.toString(),
      loanAddDate: json['loanAddDate']?.toString(),
      interestPercentage: _toDoubleNullable(json['interestPercentage']),
      installmentType: json['installmentType']?.toString(),
      note: json['note']?.toString(),
    );
  }
}

class LoanPayment {
  const LoanPayment({
    required this.id,
    required this.amount,
    required this.date,
    required this.status,
    this.loanId,
    this.loanCode,
    this.amountPaidSoFar,
    this.paymentMethod,
  });

  final int id;
  final double amount;
  final String date;
  final String status;
  final int? loanId;
  final String? loanCode;
  final double? amountPaidSoFar;
  final String? paymentMethod;

  String get formattedDate {
    final parsed = DateTime.tryParse(date);
    if (parsed == null) return date;
    return DateFormat('dd MMM yyyy').format(parsed);
  }

  String get formattedAmount => _money(amount);

  factory LoanPayment.fromJson(Map<String, dynamic> json) {
    final loan = json['loan'];
    int? loanId;
    String? loanCode;
    if (loan is Map<String, dynamic>) {
      loanId = _toIntNullable(loan['id']);
      loanCode = loan['loanId']?.toString();
    }

    return LoanPayment(
      id: _toInt(json['id']),
      amount: _toDouble(json['amount']),
      date: (json['date'] ?? json['addDate'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      loanId: loanId ?? _toIntNullable(json['loanId']),
      loanCode: loanCode,
      amountPaidSoFar: _toDoubleNullable(json['amountPaidSoFar']),
      paymentMethod: json['paymentMethod']?.toString(),
    );
  }
}

class PayrollRecord {
  const PayrollRecord({
    required this.id,
    required this.month,
    required this.netPay,
    required this.status,
    this.grossPay,
    this.netSalary,
    this.netReceivable,
    this.basics,
    this.houses,
    this.medicals,
    this.foods,
    this.sGross,
    this.mess,
    this.absentDays,
    this.holidays,
    this.leaves,
    this.presentDays,
    this.absenceDeduction,
    this.providentFund,
    this.punishment,
    this.serviceBill,
    this.tax,
    this.loan,
    this.messDeposit,
    this.others,
    this.othersPayable,
    this.adjustment,
    this.paymentMethod,
    this.designation,
    this.sectorName,
  });

  final int id;
  final String month;
  final double netPay;
  final String status;
  final double? grossPay;
  final double? netSalary;
  final double? netReceivable;
  final double? basics;
  final double? houses;
  final double? medicals;
  final double? foods;
  final double? sGross;
  final double? mess;
  final int? absentDays;
  final int? holidays;
  final int? leaves;
  final int? presentDays;
  final double? absenceDeduction;
  final double? providentFund;
  final double? punishment;
  final double? serviceBill;
  final double? tax;
  final double? loan;
  final double? messDeposit;
  final double? others;
  final double? othersPayable;
  final double? adjustment;
  final String? paymentMethod;
  final String? designation;
  final String? sectorName;

  String get formattedNet => _money(netReceivable ?? netPay);

  factory PayrollRecord.fromJson(Map<String, dynamic> json) {
    final sector = json['sector'];
    String? sectorName;
    if (sector is Map<String, dynamic>) {
      sectorName = sector['name']?.toString();
    }

    return PayrollRecord(
      id: _toInt(json['id']),
      month: (json['month'] ?? '').toString(),
      netPay: _toDouble(json['netPay'] ?? json['netSalary'] ?? json['amount']),
      status: (json['status'] ?? '').toString(),
      grossPay: _toDoubleNullable(json['grossPay'] ?? json['sGross']),
      netSalary: _toDoubleNullable(json['netSalary']),
      netReceivable: _toDoubleNullable(json['netReceivable']),
      basics: _toDoubleNullable(json['basics']),
      houses: _toDoubleNullable(json['houses']),
      medicals: _toDoubleNullable(json['medicals']),
      foods: _toDoubleNullable(json['foods']),
      sGross: _toDoubleNullable(json['sGross']),
      mess: _toDoubleNullable(json['mess']),
      absentDays: _toIntNullable(json['absentDays']),
      holidays: _toIntNullable(json['holidays']),
      leaves: _toIntNullable(json['leaves']),
      presentDays: _toIntNullable(json['presentDays']),
      absenceDeduction: _toDoubleNullable(json['absenceDeduction']),
      providentFund: _toDoubleNullable(json['providentFund']),
      punishment: _toDoubleNullable(json['punishment']),
      serviceBill: _toDoubleNullable(json['serviceBill']),
      tax: _toDoubleNullable(json['tax']),
      loan: _toDoubleNullable(json['loan']),
      messDeposit: _toDoubleNullable(json['messDeposit']),
      others: _toDoubleNullable(json['others']),
      othersPayable: _toDoubleNullable(json['othersPayable']),
      adjustment: _toDoubleNullable(json['adjustment']),
      paymentMethod: json['paymentMethod']?.toString(),
      designation: json['designation']?.toString(),
      sectorName: sectorName,
    );
  }
}

class ProvidentFundRecord {
  const ProvidentFundRecord({
    required this.id,
    required this.closingBalance,
    this.month,
    this.openingBalance,
    this.monthlyPfAmount,
    this.pfAmountTotal,
    this.pfInterestTotal,
    this.closingBalanceWithProfit,
    this.status,
    this.addDate,
  });

  final int id;
  final double closingBalance;
  final String? month;
  final double? openingBalance;
  final double? monthlyPfAmount;
  final double? pfAmountTotal;
  final double? pfInterestTotal;
  final double? closingBalanceWithProfit;
  final String? status;
  final String? addDate;

  String get formattedBalance =>
      _money(closingBalanceWithProfit ?? closingBalance);

  factory ProvidentFundRecord.fromJson(Map<String, dynamic> json) {
    return ProvidentFundRecord(
      id: _toInt(json['id']),
      closingBalance: _toDouble(json['closingBalance']),
      month: json['month']?.toString(),
      openingBalance: _toDoubleNullable(json['openingBalance']),
      monthlyPfAmount: _toDoubleNullable(json['monthlyPfAmount']),
      pfAmountTotal: _toDoubleNullable(json['pfAmountTotal']),
      pfInterestTotal: _toDoubleNullable(json['pfInterestTotal']),
      closingBalanceWithProfit:
          _toDoubleNullable(json['closingBalanceWithProfit']),
      status: json['status']?.toString(),
      addDate: json['addDate']?.toString(),
    );
  }
}

class MessDepositRecord {
  const MessDepositRecord({
    required this.id,
    required this.dAmount,
    this.messDepositId,
    this.totalDepAmount,
    this.tType,
    this.tDate,
    this.note,
    this.status,
    this.department,
  });

  final int id;
  final double dAmount;
  final String? messDepositId;
  final double? totalDepAmount;
  final String? tType;
  final String? tDate;
  final String? note;
  final String? status;
  final String? department;

  String get formattedAmount => _money(dAmount);
  String get formattedTotal => _money(totalDepAmount ?? dAmount);

  factory MessDepositRecord.fromJson(Map<String, dynamic> json) {
    return MessDepositRecord(
      id: _toInt(json['id']),
      messDepositId: json['messDepositId']?.toString(),
      dAmount: _toDouble(json['dAmount'] ?? json['amount']),
      totalDepAmount: _toDoubleNullable(json['totalDepAmount']),
      tType: json['tType']?.toString(),
      tDate: json['tDate']?.toString(),
      note: json['note']?.toString(),
      status: json['status']?.toString(),
      department: json['department']?.toString(),
    );
  }
}

class CompensationFacility {
  const CompensationFacility({
    this.basics,
    this.houses,
    this.medicals,
    this.foods,
    this.sGross,
    this.mobileBill,
    this.mess,
    this.quarter,
    this.serviceBill,
    this.loanF,
    this.tax,
    this.paymentMethod,
    this.designationName,
    this.departmentName,
    this.sectorName,
    this.jDate,
  });

  final double? basics;
  final double? houses;
  final double? medicals;
  final double? foods;
  final double? sGross;
  final double? mobileBill;
  final double? mess;
  final double? quarter;
  final double? serviceBill;
  final double? loanF;
  final double? tax;
  final String? paymentMethod;
  final String? designationName;
  final String? departmentName;
  final String? sectorName;
  final String? jDate;

  String money(double? v) => _money(v ?? 0);

  factory CompensationFacility.fromJson(Map<String, dynamic> json) {
    final designation = json['designation'];
    final department = json['department'];
    final sector = json['sector'];

    return CompensationFacility(
      basics: _toDoubleNullable(json['basics'] ?? json['basic']),
      houses: _toDoubleNullable(json['houses'] ?? json['house']),
      medicals: _toDoubleNullable(json['medicals'] ?? json['medical']),
      foods: _toDoubleNullable(json['foods'] ?? json['food']),
      sGross: _toDoubleNullable(json['sGross']),
      mobileBill: _toDoubleNullable(json['mobileBill']),
      mess: _toDoubleNullable(json['mess']),
      quarter: _toDoubleNullable(json['quarter']),
      serviceBill: _toDoubleNullable(json['serviceBill']),
      loanF: _toDoubleNullable(json['loanF']),
      tax: _toDoubleNullable(json['tax']),
      paymentMethod: json['paymentMethod']?.toString(),
      designationName: designation is Map
          ? designation['name']?.toString()
          : json['designationName']?.toString(),
      departmentName: department is Map
          ? department['name']?.toString()
          : json['departmentName']?.toString(),
      sectorName: sector is Map
          ? sector['name']?.toString()
          : json['sectorName']?.toString(),
      jDate: json['jDate']?.toString(),
    );
  }
}

class PaymentsHubSummary {
  const PaymentsHubSummary({
    this.latestNetPay,
    this.latestPayslipMonth,
    this.openLoanRemaining,
    this.pfClosingBalance,
  });

  final double? latestNetPay;
  final String? latestPayslipMonth;
  final double? openLoanRemaining;
  final double? pfClosingBalance;
}
