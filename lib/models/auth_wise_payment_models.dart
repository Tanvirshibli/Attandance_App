import 'package:intl/intl.dart';

import 'sales_models.dart' show moneyBdt;

int _toInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

int? _toIntNullable(Object? v) {
  if (v == null) return null;
  return _toInt(v);
}

double _toDouble(Object? v) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

List<Map<String, dynamic>> _mapList(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}

class AuthWisePaymentEmployee {
  const AuthWisePaymentEmployee({
    required this.id,
    required this.employeeId,
    this.employeeName,
    this.userId,
    this.userName,
  });

  final int id;
  final int employeeId;
  final String? employeeName;
  final int? userId;
  final String? userName;

  factory AuthWisePaymentEmployee.fromJson(Map<String, dynamic> json) {
    return AuthWisePaymentEmployee(
      id: _toInt(json['id']),
      employeeId: _toInt(json['employeeId'] ?? json['employee_id']),
      employeeName: (json['employeeName'] ?? json['employee_name'])?.toString(),
      userId: _toIntNullable(json['userId'] ?? json['user_id']),
      userName: (json['userName'] ?? json['user_name'])?.toString(),
    );
  }
}

class AuthWiseModuleTotal {
  const AuthWiseModuleTotal({
    required this.key,
    required this.totalPayments,
    required this.totalAmount,
  });

  final String key;
  final int totalPayments;
  final double totalAmount;

  factory AuthWiseModuleTotal.fromJson(String key, Map<String, dynamic> json) {
    return AuthWiseModuleTotal(
      key: key,
      totalPayments: _toInt(json['total_payments']),
      totalAmount: _toDouble(json['total_amount']),
    );
  }
}

class AuthWiseStatusTotal {
  const AuthWiseStatusTotal({
    required this.status,
    required this.totalPayments,
    required this.totalAmount,
  });

  final String status;
  final int totalPayments;
  final double totalAmount;

  factory AuthWiseStatusTotal.fromJson(Map<String, dynamic> json) {
    return AuthWiseStatusTotal(
      status: (json['status'] ?? '').toString(),
      totalPayments: _toInt(json['total_payments']),
      totalAmount: _toDouble(json['total_amount']),
    );
  }
}

class AuthWiseOverallSummary {
  const AuthWiseOverallSummary({
    required this.totalPayments,
    required this.classifiedPayments,
    required this.unclassifiedPayments,
    required this.totalAmount,
    required this.classifiedAmount,
    required this.unclassifiedAmount,
    required this.totalDealers,
    required this.totalCompanies,
    required this.totalPaymentModes,
    this.statuses = const [],
    this.moduleTotals = const [],
  });

  final int totalPayments;
  final int classifiedPayments;
  final int unclassifiedPayments;
  final double totalAmount;
  final double classifiedAmount;
  final double unclassifiedAmount;
  final int totalDealers;
  final int totalCompanies;
  final int totalPaymentModes;
  final List<AuthWiseStatusTotal> statuses;
  final List<AuthWiseModuleTotal> moduleTotals;

  factory AuthWiseOverallSummary.fromJson(Map<String, dynamic> json) {
    final moduleRaw = json['module_totals'];
    final modules = <AuthWiseModuleTotal>[];
    if (moduleRaw is Map) {
      for (final entry in moduleRaw.entries) {
        final value = entry.value;
        if (value is Map) {
          modules.add(
            AuthWiseModuleTotal.fromJson(
              entry.key.toString(),
              Map<String, dynamic>.from(value),
            ),
          );
        }
      }
    }

    return AuthWiseOverallSummary(
      totalPayments: _toInt(json['total_payments']),
      classifiedPayments: _toInt(json['classified_payments']),
      unclassifiedPayments: _toInt(json['unclassified_payments']),
      totalAmount: _toDouble(json['total_amount']),
      classifiedAmount: _toDouble(json['classified_amount']),
      unclassifiedAmount: _toDouble(json['unclassified_amount']),
      totalDealers: _toInt(json['total_dealers']),
      totalCompanies: _toInt(json['total_companies']),
      totalPaymentModes: _toInt(json['total_payment_modes']),
      statuses: _mapList(json['statuses']).map(AuthWiseStatusTotal.fromJson).toList(),
      moduleTotals: modules,
    );
  }
}

class AuthWiseModuleSummary {
  const AuthWiseModuleSummary({
    required this.totalPayments,
    required this.totalAmount,
    required this.totalDealers,
    required this.totalCompanies,
    required this.totalPaymentModes,
  });

  final int totalPayments;
  final double totalAmount;
  final int totalDealers;
  final int totalCompanies;
  final int totalPaymentModes;

  bool get isEmpty => totalPayments == 0 && totalAmount == 0;

  factory AuthWiseModuleSummary.fromJson(Map<String, dynamic> json) {
    return AuthWiseModuleSummary(
      totalPayments: _toInt(json['total_payments']),
      totalAmount: _toDouble(json['total_amount']),
      totalDealers: _toInt(json['total_dealers']),
      totalCompanies: _toInt(json['total_companies']),
      totalPaymentModes: _toInt(json['total_payment_modes']),
    );
  }
}

class AuthWiseNamedTotal {
  const AuthWiseNamedTotal({
    required this.id,
    required this.name,
    required this.totalPayments,
    required this.totalAmount,
  });

  final int id;
  final String name;
  final int totalPayments;
  final double totalAmount;

  factory AuthWiseNamedTotal.fromJson(Map<String, dynamic> json) {
    return AuthWiseNamedTotal(
      id: _toInt(json['id']),
      name: (json['name'] ?? '').toString(),
      totalPayments: _toInt(json['total_payments']),
      totalAmount: _toDouble(json['total_amount']),
    );
  }
}

class AuthWisePaymentMethodTotal {
  const AuthWisePaymentMethodTotal({
    required this.totalPayments,
    required this.totalAmount,
    this.paymentMode,
    this.paymentTypeId,
    this.bankName,
    this.bankShortName,
    this.bankAccountNo,
  });

  final int? paymentMode;
  final int? paymentTypeId;
  final String? bankName;
  final String? bankShortName;
  final String? bankAccountNo;
  final int totalPayments;
  final double totalAmount;

  String get label {
    final bank = bankShortName?.trim().isNotEmpty == true
        ? bankShortName!.trim()
        : (bankName?.trim().isNotEmpty == true ? bankName!.trim() : null);
    if (bank != null) return bank;
    if (paymentMode != null) return 'Mode $paymentMode';
    return 'Payment method';
  }

  factory AuthWisePaymentMethodTotal.fromJson(Map<String, dynamic> json) {
    return AuthWisePaymentMethodTotal(
      paymentMode: _toIntNullable(json['payment_mode']),
      paymentTypeId: _toIntNullable(json['payment_type_id']),
      bankName: json['bank_name']?.toString(),
      bankShortName: json['bank_short_name']?.toString(),
      bankAccountNo: json['bank_account_no']?.toString(),
      totalPayments: _toInt(json['total_payments']),
      totalAmount: _toDouble(json['total_amount']),
    );
  }
}

class AuthWisePaymentLine {
  const AuthWisePaymentLine({
    required this.id,
    required this.amount,
    required this.module,
    this.voucherNo,
    this.receiveDate,
    this.status,
    this.companyName,
    this.dealerName,
    this.paymentForName,
    this.bankName,
    this.bankShortName,
    this.checkNo,
    this.reference,
    this.authByName,
    this.note,
  });

  final int id;
  final String? voucherNo;
  final String? receiveDate;
  final double amount;
  final String? status;
  final String? companyName;
  final String? dealerName;
  final String? paymentForName;
  final String? bankName;
  final String? bankShortName;
  final String? checkNo;
  final String? reference;
  final String? authByName;
  final String? note;
  final String module;

  String get formattedDate {
    final parsed = DateTime.tryParse(receiveDate ?? '');
    if (parsed == null) return receiveDate ?? '—';
    return DateFormat('dd MMM yyyy').format(parsed);
  }

  String get formattedAmount => moneyBdt(amount);

  factory AuthWisePaymentLine.fromJson(Map<String, dynamic> json) {
    return AuthWisePaymentLine(
      id: _toInt(json['id']),
      voucherNo: json['voucher_no']?.toString(),
      receiveDate: json['receive_date']?.toString(),
      amount: _toDouble(json['amount']),
      status: json['status']?.toString(),
      companyName: json['company_name']?.toString(),
      dealerName: json['dealer_name']?.toString(),
      paymentForName: json['payment_for_name']?.toString(),
      bankName: json['bank_name']?.toString(),
      bankShortName: json['bank_short_name']?.toString(),
      checkNo: json['check_no']?.toString(),
      reference: json['reference']?.toString(),
      authByName: json['auth_by_name']?.toString(),
      note: json['note']?.toString(),
      module: (json['module'] ?? '').toString(),
    );
  }
}

class AuthWisePaymentModule {
  const AuthWisePaymentModule({
    required this.key,
    required this.label,
    required this.summary,
    required this.dealers,
    required this.companies,
    required this.paymentFor,
    required this.paymentMethods,
    required this.statuses,
    required this.details,
  });

  final String key;
  final String label;
  final AuthWiseModuleSummary summary;
  final List<AuthWiseNamedTotal> dealers;
  final List<AuthWiseNamedTotal> companies;
  final List<AuthWiseNamedTotal> paymentFor;
  final List<AuthWisePaymentMethodTotal> paymentMethods;
  final List<AuthWiseStatusTotal> statuses;
  final List<AuthWisePaymentLine> details;

  bool get isEmpty =>
      summary.isEmpty && details.isEmpty && dealers.isEmpty && companies.isEmpty;

  factory AuthWisePaymentModule.fromJson(
    String key,
    String label,
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return AuthWisePaymentModule(
        key: key,
        label: label,
        summary: AuthWiseModuleSummary.fromJson(const {}),
        dealers: const [],
        companies: const [],
        paymentFor: const [],
        paymentMethods: const [],
        statuses: const [],
        details: const [],
      );
    }

    final summaryRaw = json['summary'];
    final linesRaw = json['data'];
    return AuthWisePaymentModule(
      key: key,
      label: label,
      summary: AuthWiseModuleSummary.fromJson(
        summaryRaw is Map<String, dynamic> ? summaryRaw : const {},
      ),
      dealers: _mapList(json['dealers']).map(AuthWiseNamedTotal.fromJson).toList(),
      companies:
          _mapList(json['companies']).map(AuthWiseNamedTotal.fromJson).toList(),
      paymentFor:
          _mapList(json['payment_for']).map(AuthWiseNamedTotal.fromJson).toList(),
      paymentMethods: _mapList(json['payment_methods'])
          .map(AuthWisePaymentMethodTotal.fromJson)
          .toList(),
      statuses:
          _mapList(json['statuses']).map(AuthWiseStatusTotal.fromJson).toList(),
      details:
          _mapList(linesRaw).map(AuthWisePaymentLine.fromJson).toList(),
    );
  }
}

class AuthWisePaymentsData {
  const AuthWisePaymentsData({
    required this.employee,
    required this.fromDate,
    required this.toDate,
    required this.overall,
    required this.modules,
  });

  final AuthWisePaymentEmployee employee;
  final String fromDate;
  final String toDate;
  final AuthWiseOverallSummary overall;
  final List<AuthWisePaymentModule> modules;

  factory AuthWisePaymentsData.fromJson(Map<String, dynamic> json) {
    final employeeRaw = json['employee'];
    final filters = json['filters'];
    final overallRaw = json['overall'];

    const moduleDefs = <(String, String)>[
      ('egg', 'Egg'),
      ('feed', 'Feed'),
      ('fertilizer', 'Fertilizer'),
      ('chicks', 'Chicks'),
      ('liveBird', 'Live Bird'),
      ('cullBird', 'Cull Bird'),
      ('unclassified', 'Other'),
    ];

    return AuthWisePaymentsData(
      employee: AuthWisePaymentEmployee.fromJson(
        employeeRaw is Map<String, dynamic> ? employeeRaw : const {},
      ),
      fromDate: filters is Map<String, dynamic>
          ? (filters['from_date'] ?? '').toString()
          : '',
      toDate: filters is Map<String, dynamic>
          ? (filters['to_date'] ?? '').toString()
          : '',
      overall: AuthWiseOverallSummary.fromJson(
        overallRaw is Map<String, dynamic> ? overallRaw : const {},
      ),
      modules: [
        for (final def in moduleDefs)
          AuthWisePaymentModule.fromJson(
            def.$1,
            def.$2,
            json[def.$1] is Map<String, dynamic>
                ? json[def.$1] as Map<String, dynamic>
                : null,
          ),
      ],
    );
  }
}
