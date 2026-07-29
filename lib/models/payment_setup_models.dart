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

  factory SetupCompany.fromJson(Map<String, dynamic> json) {
    return SetupCompany(
      id: _toInt(json['id']),
      nameEn: json['nameEn']?.toString(),
    );
  }
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
}

class SetupEmployee {
  const SetupEmployee({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    this.phoneNumber,
    this.companyName,
  });

  /// Auth-wise receiver id (POST `receiverId`).
  final int id;
  final int employeeId;
  final String employeeName;
  final String? phoneNumber;
  final String? companyName;

  String get searchText =>
      '${employeeName.toLowerCase()} $employeeId ${phoneNumber ?? ''} '
      '${companyName?.toLowerCase() ?? ''}';

  factory SetupEmployee.fromJson(Map<String, dynamic> json) {
    return SetupEmployee(
      id: _toInt(json['id']),
      employeeId: _toInt(json['employeeId']),
      employeeName: json['employeeName']?.toString() ?? 'Employee',
      phoneNumber: json['phone_number']?.toString(),
      companyName: json['companyName']?.toString(),
    );
  }
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
}

int _toInt(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
