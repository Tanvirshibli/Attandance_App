class AuthWisePaymentLineInput {
  const AuthWisePaymentLineInput({
    required this.companyId,
    required this.recType,
    required this.receiverId,
    required this.amount,
    required this.recDate,
    required this.paymentType,
    required this.paymentMode,
    required this.paymentFor,
    required this.invoiceType,
    this.note,
    this.trxId,
    this.ref,
    this.checkNo,
    this.checkDate,
  });

  final int companyId;
  final int recType;
  final int receiverId;
  final double amount;
  final String recDate;
  final int paymentType;
  final int paymentMode;
  final int paymentFor;
  final int invoiceType;
  final String? note;
  final String? trxId;
  final String? ref;
  final String? checkNo;
  final String? checkDate;
}

class CreateAuthWisePaymentRequest {
  const CreateAuthWisePaymentRequest({
    required this.employeeId,
    required this.payments,
  });

  final int employeeId;
  final List<AuthWisePaymentLineInput> payments;

  Map<String, String> toFormFields() {
    final fields = <String, String>{'employeeId': '$employeeId'};

    for (var i = 0; i < payments.length; i++) {
      final p = payments[i];
      final prefix = 'payments[$i]';
      fields['$prefix[companyId]'] = '${p.companyId}';
      fields['$prefix[recType]'] = '${p.recType}';
      fields['$prefix[receiverId]'] = '${p.receiverId}';
      fields['$prefix[amount]'] = _num(p.amount);
      fields['$prefix[recDate]'] = p.recDate;
      fields['$prefix[paymentType]'] = '${p.paymentType}';
      fields['$prefix[paymentMode]'] = '${p.paymentMode}';
      fields['$prefix[paymentFor]'] = '${p.paymentFor}';
      fields['$prefix[invoiceType]'] = '${p.invoiceType}';
      _put(fields, '$prefix[note]', p.note);
      _put(fields, '$prefix[trxId]', p.trxId);
      _put(fields, '$prefix[ref]', p.ref);
      _put(fields, '$prefix[checkNo]', p.checkNo);
      _put(fields, '$prefix[checkDate]', p.checkDate);
    }

    return fields;
  }

  static void _put(Map<String, String> fields, String key, String? value) {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      fields[key] = trimmed;
    }
  }

  static String _num(num value) {
    if (value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toString();
  }
}

class AuthWisePaymentCreated {
  const AuthWisePaymentCreated({
    required this.createdPaymentCount,
    required this.voucherNos,
    required this.message,
  });

  final int createdPaymentCount;
  final List<String> voucherNos;
  final String message;

  factory AuthWisePaymentCreated.fromResponse(Map<String, dynamic> json) {
    final data = json['data'];
    final vouchers = <String>[];
    var count = 0;
    if (data is Map<String, dynamic>) {
      count = _int(data['createdPaymentCount']);
      final payments = data['payments'];
      if (payments is List) {
        for (final item in payments) {
          if (item is Map) {
            final v = item['voucherNo'] ?? item['voucher_no'];
            if (v != null && v.toString().isNotEmpty) {
              vouchers.add(v.toString());
            }
          }
        }
      }
    }
    return AuthWisePaymentCreated(
      createdPaymentCount: count,
      voucherNos: vouchers,
      message: json['message']?.toString() ?? 'Payment submitted.',
    );
  }

  static int _int(Object? v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}
