import 'auth_wise_payment_models.dart';

int _int(Object? v) {
  if (v is int) return v;
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

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

class AuthWiseCreatedPayment {
  const AuthWiseCreatedPayment({
    required this.id,
    this.voucherNo,
    this.amount,
    this.status,
    this.image,
  });

  final int id;
  final String? voucherNo;
  final double? amount;
  final String? status;
  final AuthWisePaymentImage? image;

  factory AuthWiseCreatedPayment.fromJson(Map<String, dynamic> json) {
    return AuthWiseCreatedPayment(
      id: _int(json['id']),
      voucherNo:
          (json['voucherNo'] ?? json['voucher_no'])?.toString(),
      amount: json['amount'] is num ? (json['amount'] as num).toDouble() : null,
      status: json['status']?.toString(),
      image: json['image'] is Map<String, dynamic>
          ? AuthWisePaymentImage.fromJson(
              json['image'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

class AuthWisePaymentCreated {
  const AuthWisePaymentCreated({
    required this.createdPaymentCount,
    required this.voucherNos,
    required this.message,
    this.employee,
    this.payments = const [],
  });

  final int createdPaymentCount;
  final List<String> voucherNos;
  final String message;
  final AuthWisePaymentEmployee? employee;
  final List<AuthWiseCreatedPayment> payments;

  /// How many created payments came back with an attached receipt image.
  int get attachedImageCount =>
      payments.where((p) => p.image != null).length;

  factory AuthWisePaymentCreated.fromResponse(Map<String, dynamic> json) {
    final data = json['data'];
    final vouchers = <String>[];
    final payments = <AuthWiseCreatedPayment>[];
    var count = 0;
    AuthWisePaymentEmployee? employee;
    if (data is Map<String, dynamic>) {
      count = _int(data['createdPaymentCount']);
      if (data['employee'] is Map<String, dynamic>) {
        employee = AuthWisePaymentEmployee.fromJson(
          data['employee'] as Map<String, dynamic>,
        );
      }
      final paymentsRaw = data['payments'];
      if (paymentsRaw is List) {
        for (final item in paymentsRaw) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);
            payments.add(AuthWiseCreatedPayment.fromJson(map));
            final v = map['voucherNo'] ?? map['voucher_no'];
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
      employee: employee,
      payments: payments,
    );
  }
}
