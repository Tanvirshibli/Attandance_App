class PaymentSetupData {
  const PaymentSetupData({
    required this.banks,
    required this.employees,
    required this.paymentTypes,
  });

  final List<SetupBank> banks;
  final List<SetupEmployee> employees;
  final List<SetupPaymentType> paymentTypes;

  factory PaymentSetupData.fromJson(Map<String, dynamic> json) {
    return PaymentSetupData(
      banks: _mapList(json['bankList']).map(SetupBank.fromJson).toList(),
      employees:
          _mapList(json['employeeList']).map(SetupEmployee.fromJson).toList(),
      paymentTypes: _mapList(json['paymentTypeList'])
          .map(SetupPaymentType.fromJson)
          .toList(),
    );
  }

  List<SetupCompany> get uniqueCompanies {
    final byId = <int, SetupCompany>{};
    for (final bank in banks) {
      final company = bank.company;
      if (company != null && company.id > 0) {
        byId[company.id] = company;
      }
    }
    final list = byId.values.toList()
      ..sort(
        (a, b) => a.displayLabel.toLowerCase().compareTo(
              b.displayLabel.toLowerCase(),
            ),
      );
    return list;
  }

  static List<Map<String, dynamic>> _mapList(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}

class SetupCompany {
  const SetupCompany({required this.id, this.nameEn});

  final int id;
  final String? nameEn;

  String get displayLabel {
    final name = nameEn?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'Company $id';
  }

  String get searchText => displayLabel.toLowerCase();

  factory SetupCompany.fromJson(Map<String, dynamic> json) {
    return SetupCompany(
      id: _toInt(json['id']),
      nameEn: json['nameEn']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) => other is SetupCompany && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class SetupBank {
  const SetupBank({
    required this.id,
    required this.bankName,
    this.shortName,
    this.company,
  });

  final int id;
  final String bankName;
  final String? shortName;
  final SetupCompany? company;

  String get displayLabel {
    final short = shortName?.trim();
    if (short != null && short.isNotEmpty) {
      return '$bankName ($short)';
    }
    return bankName;
  }

  String get searchText =>
      '${bankName.toLowerCase()} ${shortName?.toLowerCase() ?? ''} '
      '${company?.nameEn?.toLowerCase() ?? ''}';

  factory SetupBank.fromJson(Map<String, dynamic> json) {
    final companyRaw = json['company'];
    return SetupBank(
      id: _toInt(json['id']),
      bankName: json['bankName']?.toString() ?? 'Bank',
      shortName: json['shortName']?.toString(),
      company: companyRaw is Map<String, dynamic>
          ? SetupCompany.fromJson(companyRaw)
          : companyRaw is Map
              ? SetupCompany.fromJson(Map<String, dynamic>.from(companyRaw))
              : null,
    );
  }

  @override
  bool operator ==(Object other) => other is SetupBank && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class SetupEmployee {
  const SetupEmployee({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    this.phoneNumber,
    this.companyName,
    this.currentBalance,
    this.ledgerName,
  });

  /// `sales_employees_flat.id` — chicks `bookingPerson`.
  final int id;

  /// HRM / `users.employeeId` — auth-wise `receiverId` when recType is employee.
  final int employeeId;
  final String employeeName;
  final String? phoneNumber;
  final String? companyName;
  final double? currentBalance;
  final String? ledgerName;

  String get searchText =>
      '${employeeName.toLowerCase()} $employeeId ${phoneNumber ?? ''} '
      '${companyName?.toLowerCase() ?? ''} ${ledgerName?.toLowerCase() ?? ''}';

  String get subtitle {
    final parts = <String>[
      'Emp $employeeId',
      if (ledgerName != null && ledgerName!.trim().isNotEmpty) ledgerName!.trim(),
      if (currentBalance != null)
        'Bal ৳${currentBalance == currentBalance!.roundToDouble() ? currentBalance!.round() : currentBalance!.toStringAsFixed(2)}',
    ];
    return parts.join(' · ');
  }

  factory SetupEmployee.fromJson(Map<String, dynamic> json) {
    return SetupEmployee(
      id: _toInt(json['id']),
      employeeId: _toInt(json['employeeId']),
      employeeName: json['employeeName']?.toString() ?? 'Employee',
      phoneNumber: json['phone_number']?.toString(),
      companyName: json['companyName']?.toString(),
      currentBalance: _toDouble(
        json['current_balance'] ?? json['currentBalance'],
      ),
      ledgerName: json['ledger_name']?.toString() ?? json['ledgerName']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) => other is SetupEmployee && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class SetupPaymentType {
  const SetupPaymentType({required this.id, required this.name});

  final int id;
  final String name;

  String get searchText => name.toLowerCase();

  factory SetupPaymentType.fromJson(Map<String, dynamic> json) {
    return SetupPaymentType(
      id: _toInt(json['id']),
      name: json['name']?.toString() ?? 'Type',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SetupPaymentType && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

int _toInt(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double? _toDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
