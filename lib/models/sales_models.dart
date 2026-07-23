import 'package:intl/intl.dart';

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

double? _toDoubleNullable(Object? v) {
  if (v == null) return null;
  return _toDouble(v);
}

String moneyBdt(num value, {int decimals = 0}) {
  return NumberFormat.currency(symbol: '৳', decimalDigits: decimals).format(value);
}

String qtyFmt(num value) {
  if (value == value.roundToDouble()) {
    return NumberFormat('#,##0').format(value);
  }
  return NumberFormat('#,##0.##').format(value);
}

/// Kept for Post Sale demo flow until a live create API exists.
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

  String get formattedAmount => moneyBdt(amount);

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

class SalesPersonEmployee {
  const SalesPersonEmployee({
    required this.inputId,
    required this.employeeId,
    this.id,
    this.matchedBy,
    this.employeeName,
  });

  final int inputId;
  final int employeeId;
  final int? id;
  final String? matchedBy;
  final String? employeeName;

  factory SalesPersonEmployee.fromJson(Map<String, dynamic> json) {
    return SalesPersonEmployee(
      inputId: _toInt(json['input_id'] ?? json['inputId']),
      employeeId: _toInt(json['employee_id'] ?? json['employeeId']),
      id: _toIntNullable(json['id']),
      matchedBy: (json['matched_by'] ?? json['matchedBy'])?.toString(),
      employeeName: (json['employee_name'] ?? json['employeeName'])?.toString(),
    );
  }
}

class SalesQtyByUnit {
  const SalesQtyByUnit({
    required this.netQty,
    this.unitId,
    this.unitName,
    this.grossQty = 0,
    this.returnQty = 0,
  });

  final int? unitId;
  final String? unitName;
  final double grossQty;
  final double returnQty;
  final double netQty;

  String get label {
    final unit = unitName?.trim();
    if (unit == null || unit.isEmpty) return qtyFmt(netQty);
    return '${qtyFmt(netQty)} $unit';
  }

  factory SalesQtyByUnit.fromJson(Map<String, dynamic> json) {
    return SalesQtyByUnit(
      unitId: _toIntNullable(json['unit_id']),
      unitName: json['unit_name']?.toString(),
      grossQty: _toDouble(json['gross_qty']),
      returnQty: _toDouble(json['return_qty']),
      netQty: _toDouble(json['net_qty']),
    );
  }
}

class SalesOverallSummary {
  const SalesOverallSummary({
    required this.totalOrders,
    required this.totalReturns,
    required this.totalDetails,
    required this.grossQty,
    required this.returnQty,
    required this.netQty,
    required this.deliveredQty,
    required this.pcsQty,
    required this.scaleWeight,
    required this.grossSales,
    required this.salesReturn,
    required this.netSales,
    required this.invoiceNetTotal,
    this.quantityByUnit = const [],
  });

  final int totalOrders;
  final int totalReturns;
  final int totalDetails;
  final double grossQty;
  final double returnQty;
  final double netQty;
  final double deliveredQty;
  final double pcsQty;
  final double scaleWeight;
  final double grossSales;
  final double salesReturn;
  final double netSales;
  final double invoiceNetTotal;
  final List<SalesQtyByUnit> quantityByUnit;

  factory SalesOverallSummary.fromJson(Map<String, dynamic> json) {
    final byUnitRaw = json['quantity_by_unit'];
    final byUnit = byUnitRaw is List
        ? byUnitRaw
            .whereType<Map<String, dynamic>>()
            .map(SalesQtyByUnit.fromJson)
            .toList()
        : const <SalesQtyByUnit>[];

    return SalesOverallSummary(
      totalOrders: _toInt(json['total_orders']),
      totalReturns: _toInt(json['total_returns']),
      totalDetails: _toInt(json['total_details']),
      grossQty: _toDouble(json['gross_qty']),
      returnQty: _toDouble(json['return_qty']),
      netQty: _toDouble(json['net_qty']),
      deliveredQty: _toDouble(json['delivered_qty']),
      pcsQty: _toDouble(json['pcs_qty']),
      scaleWeight: _toDouble(json['scale_weight']),
      grossSales: _toDouble(json['gross_sales']),
      salesReturn: _toDouble(json['sales_return']),
      netSales: _toDouble(json['net_sales']),
      invoiceNetTotal: _toDouble(json['invoice_net_total']),
      quantityByUnit: byUnit,
    );
  }
}

class SalesModuleSummary {
  const SalesModuleSummary({
    required this.totalOrders,
    required this.totalReturns,
    required this.totalDetails,
    required this.totalProducts,
    required this.totalDealers,
    required this.totalSectors,
    required this.grossQty,
    required this.returnQty,
    required this.netQty,
    required this.deliveredQty,
    required this.pcsQty,
    required this.scaleWeight,
    required this.grossSales,
    required this.salesReturn,
    required this.netSales,
    required this.invoiceNetTotal,
  });

  final int totalOrders;
  final int totalReturns;
  final int totalDetails;
  final int totalProducts;
  final int totalDealers;
  final int totalSectors;
  final double grossQty;
  final double returnQty;
  final double netQty;
  final double deliveredQty;
  final double pcsQty;
  final double scaleWeight;
  final double grossSales;
  final double salesReturn;
  final double netSales;
  final double invoiceNetTotal;

  bool get isEmpty =>
      totalOrders == 0 &&
      totalReturns == 0 &&
      totalDetails == 0 &&
      netSales == 0 &&
      netQty == 0;

  factory SalesModuleSummary.fromJson(Map<String, dynamic> json) {
    return SalesModuleSummary(
      totalOrders: _toInt(json['total_orders']),
      totalReturns: _toInt(json['total_returns']),
      totalDetails: _toInt(json['total_details']),
      totalProducts: _toInt(json['total_products']),
      totalDealers: _toInt(json['total_dealers']),
      totalSectors: _toInt(json['total_sectors']),
      grossQty: _toDouble(json['gross_qty']),
      returnQty: _toDouble(json['return_qty']),
      netQty: _toDouble(json['net_qty']),
      deliveredQty: _toDouble(json['delivered_qty']),
      pcsQty: _toDouble(json['pcs_qty']),
      scaleWeight: _toDouble(json['scale_weight']),
      grossSales: _toDouble(json['gross_sales']),
      salesReturn: _toDouble(json['sales_return']),
      netSales: _toDouble(json['net_sales']),
      invoiceNetTotal: _toDouble(json['invoice_net_total']),
    );
  }
}

class SalesProductRow {
  const SalesProductRow({
    required this.id,
    required this.name,
    required this.totalOrders,
    required this.totalReturns,
    required this.grossQty,
    required this.returnQty,
    required this.netQty,
    required this.deliveredQty,
    required this.pcsQty,
    required this.scaleWeight,
    required this.grossAmount,
    required this.returnAmount,
    required this.netAmount,
    this.unitId,
    this.unitName,
    this.packageSize,
  });

  final int id;
  final String name;
  final int totalOrders;
  final int totalReturns;
  final double grossQty;
  final double returnQty;
  final double netQty;
  final double deliveredQty;
  final double pcsQty;
  final double scaleWeight;
  final double grossAmount;
  final double returnAmount;
  final double netAmount;
  final int? unitId;
  final String? unitName;
  final double? packageSize;

  factory SalesProductRow.fromJson(Map<String, dynamic> json) {
    return SalesProductRow(
      id: _toInt(json['id']),
      name: (json['name'] ?? '').toString(),
      totalOrders: _toInt(json['total_orders']),
      totalReturns: _toInt(json['total_returns']),
      grossQty: _toDouble(json['gross_qty']),
      returnQty: _toDouble(json['return_qty']),
      netQty: _toDouble(json['net_qty']),
      deliveredQty: _toDouble(json['delivered_qty']),
      pcsQty: _toDouble(json['pcs_qty']),
      scaleWeight: _toDouble(json['scale_weight']),
      grossAmount: _toDouble(json['gross_amount']),
      returnAmount: _toDouble(json['return_amount']),
      netAmount: _toDouble(json['net_amount']),
      unitId: _toIntNullable(json['unit_id']),
      unitName: json['unit_name']?.toString(),
      packageSize: _toDoubleNullable(json['package_size']),
    );
  }
}

class SalesPartyRow {
  const SalesPartyRow({
    required this.id,
    required this.name,
    required this.totalOrders,
    required this.totalReturns,
    required this.grossQty,
    required this.returnQty,
    required this.netQty,
    required this.deliveredQty,
    required this.pcsQty,
    required this.scaleWeight,
    required this.grossAmount,
    required this.returnAmount,
    required this.netAmount,
  });

  final int id;
  final String name;
  final int totalOrders;
  final int totalReturns;
  final double grossQty;
  final double returnQty;
  final double netQty;
  final double deliveredQty;
  final double pcsQty;
  final double scaleWeight;
  final double grossAmount;
  final double returnAmount;
  final double netAmount;

  factory SalesPartyRow.fromJson(Map<String, dynamic> json) {
    return SalesPartyRow(
      id: _toInt(json['id']),
      name: (json['name'] ?? '').toString(),
      totalOrders: _toInt(json['total_orders']),
      totalReturns: _toInt(json['total_returns']),
      grossQty: _toDouble(json['gross_qty']),
      returnQty: _toDouble(json['return_qty']),
      netQty: _toDouble(json['net_qty']),
      deliveredQty: _toDouble(json['delivered_qty']),
      pcsQty: _toDouble(json['pcs_qty']),
      scaleWeight: _toDouble(json['scale_weight']),
      grossAmount: _toDouble(json['gross_amount']),
      returnAmount: _toDouble(json['return_amount']),
      netAmount: _toDouble(json['net_amount']),
    );
  }
}

class SalesDetailLine {
  const SalesDetailLine({
    required this.module,
    required this.orderId,
    required this.referenceNo,
    required this.detailId,
    required this.type,
    required this.invoiceDate,
    required this.status,
    required this.qty,
    required this.lineAmount,
    this.companyName,
    this.sectorName,
    this.saleCategoryName,
    this.dealerName,
    this.productName,
    this.unitName,
    this.unitPrice,
    this.deliveredQty,
    this.pcsQty,
    this.invoiceTotal,
  });

  final String module;
  final int orderId;
  final String referenceNo;
  final int detailId;
  final String type;
  final String invoiceDate;
  final String status;
  final double qty;
  final double lineAmount;
  final String? companyName;
  final String? sectorName;
  final String? saleCategoryName;
  final String? dealerName;
  final String? productName;
  final String? unitName;
  final double? unitPrice;
  final double? deliveredQty;
  final double? pcsQty;
  final double? invoiceTotal;

  String get formattedDate {
    final parsed = DateTime.tryParse(invoiceDate);
    if (parsed == null) return invoiceDate;
    return DateFormat('dd MMM yyyy').format(parsed);
  }

  factory SalesDetailLine.fromJson(Map<String, dynamic> json) {
    return SalesDetailLine(
      module: (json['module'] ?? '').toString(),
      orderId: _toInt(json['order_id']),
      referenceNo: (json['reference_no'] ?? '').toString(),
      detailId: _toInt(json['detail_id']),
      type: (json['type'] ?? '').toString(),
      invoiceDate: (json['invoice_date'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      qty: _toDouble(json['qty']),
      lineAmount: _toDouble(json['line_amount']),
      companyName: json['company_name']?.toString(),
      sectorName: json['sector_name']?.toString(),
      saleCategoryName: json['sale_category_name']?.toString(),
      dealerName: json['dealer_name']?.toString(),
      productName: json['product_name']?.toString(),
      unitName: json['unit_name']?.toString(),
      unitPrice: _toDoubleNullable(json['unit_price']),
      deliveredQty: _toDoubleNullable(json['delivered_qty']),
      pcsQty: _toDoubleNullable(json['pcs_qty']),
      invoiceTotal: _toDoubleNullable(json['invoice_total']),
    );
  }
}

class SalesModuleBlock {
  const SalesModuleBlock({
    required this.key,
    required this.label,
    required this.summary,
    required this.products,
    required this.dealers,
    required this.sectors,
    required this.details,
  });

  final String key;
  final String label;
  final SalesModuleSummary summary;
  final List<SalesProductRow> products;
  final List<SalesPartyRow> dealers;
  final List<SalesPartyRow> sectors;
  final List<SalesDetailLine> details;

  bool get isEmpty => summary.isEmpty && details.isEmpty && products.isEmpty;

  factory SalesModuleBlock.fromJson(
    String key,
    String label,
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return SalesModuleBlock(
        key: key,
        label: label,
        summary: SalesModuleSummary.fromJson(const {}),
        products: const [],
        dealers: const [],
        sectors: const [],
        details: const [],
      );
    }

    final summaryRaw = json['summary'];
    final linesRaw = json['data'] ?? json['details'];
    return SalesModuleBlock(
      key: key,
      label: label,
      summary: SalesModuleSummary.fromJson(
        summaryRaw is Map<String, dynamic> ? summaryRaw : const {},
      ),
      products: (json['products'] is List)
          ? (json['products'] as List)
              .whereType<Map<String, dynamic>>()
              .map(SalesProductRow.fromJson)
              .toList()
          : const [],
      dealers: (json['dealers'] is List)
          ? (json['dealers'] as List)
              .whereType<Map<String, dynamic>>()
              .map(SalesPartyRow.fromJson)
              .toList()
          : const [],
      sectors: (json['sectors'] is List)
          ? (json['sectors'] as List)
              .whereType<Map<String, dynamic>>()
              .map(SalesPartyRow.fromJson)
              .toList()
          : const [],
      details: (linesRaw is List)
          ? linesRaw
              .whereType<Map<String, dynamic>>()
              .map(SalesDetailLine.fromJson)
              .toList()
          : const [],
    );
  }
}

class SalesPersonSalesData {
  const SalesPersonSalesData({
    required this.employee,
    required this.fromDate,
    required this.toDate,
    required this.overall,
    required this.modules,
  });

  final SalesPersonEmployee employee;
  final String fromDate;
  final String toDate;
  final SalesOverallSummary overall;
  final List<SalesModuleBlock> modules;

  factory SalesPersonSalesData.fromJson(Map<String, dynamic> json) {
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
    ];

    return SalesPersonSalesData(
      employee: SalesPersonEmployee.fromJson(
        employeeRaw is Map<String, dynamic> ? employeeRaw : const {},
      ),
      fromDate: filters is Map<String, dynamic>
          ? (filters['from_date'] ?? '').toString()
          : '',
      toDate: filters is Map<String, dynamic>
          ? (filters['to_date'] ?? '').toString()
          : '',
      overall: SalesOverallSummary.fromJson(
        overallRaw is Map<String, dynamic> ? overallRaw : const {},
      ),
      modules: [
        for (final def in moduleDefs)
          SalesModuleBlock.fromJson(
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
