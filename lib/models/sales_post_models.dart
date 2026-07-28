class SalesOrderLineInput {
  const SalesOrderLineInput({
    required this.productId,
    required this.tradePrice,
    required this.salePrice,
    required this.qty,
    required this.unitId,
    this.unitBatchNo,
  });

  final int productId;
  final double tradePrice;
  final double salePrice;
  final double qty;
  final int unitId;
  final String? unitBatchNo;
}

class CreateSalesPersonOrderRequest {
  const CreateSalesPersonOrderRequest({
    required this.module,
    required this.salesPersonId,
    required this.dealerId,
    required this.salesPointId,
    required this.companyId,
    required this.totalAmount,
    required this.invoiceDate,
    required this.dueDate,
    required this.saleType,
    required this.lines,
  });

  final String module;
  final int salesPersonId;
  final int dealerId;
  final int salesPointId;
  final int companyId;
  final double totalAmount;
  final String invoiceDate;
  final String dueDate;
  final String saleType;
  final List<SalesOrderLineInput> lines;

  Map<String, String> toFormFields() {
    final fields = <String, String>{
      'module': module,
      'salesPersonId': '$salesPersonId',
      'dealerId': '$dealerId',
      'salesPointId': '$salesPointId',
      'companyId': '$companyId',
      'totalAmount': _num(totalAmount),
      'invoiceDate': invoiceDate,
      'dueDate': dueDate,
      'saleType': saleType,
    };

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final prefix = 'details[$i]';
      fields['$prefix[productId]'] = '${line.productId}';
      fields['$prefix[tradePrice]'] = _num(line.tradePrice);
      fields['$prefix[salePrice]'] = _num(line.salePrice);
      fields['$prefix[qty]'] = _num(line.qty);
      fields['$prefix[unitId]'] = '${line.unitId}';
      final batch = line.unitBatchNo?.trim();
      if (batch != null && batch.isNotEmpty) {
        fields['$prefix[unitBatchNo]'] = batch;
      }
    }

    return fields;
  }

  static String _num(num value) {
    if (value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toString();
  }
}

class SalesPersonOrderCreated {
  const SalesPersonOrderCreated({
    required this.module,
    required this.id,
    required this.referenceNo,
    required this.status,
    required this.salesPerson,
    required this.totalAmount,
    this.message,
  });

  final String module;
  final int id;
  final String referenceNo;
  final String status;
  final int salesPerson;
  final double totalAmount;
  final String? message;

  factory SalesPersonOrderCreated.fromJson(Map<String, dynamic> json) {
    return SalesPersonOrderCreated(
      module: (json['module'] ?? '').toString(),
      id: _int(json['id']),
      referenceNo: (json['reference_no'] ?? json['referenceNo'] ?? '')
          .toString(),
      status: (json['status'] ?? '').toString(),
      salesPerson: _int(json['salesPerson'] ?? json['sales_person']),
      totalAmount: _double(json['totalAmount'] ?? json['total_amount']),
    );
  }

  static int _int(Object? v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double _double(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }
}
