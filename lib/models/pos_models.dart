enum PosDocType {
  invoice,
  challan,
}

extension PosDocTypeLabel on PosDocType {
  String get label => this == PosDocType.invoice ? 'POS Invoice' : 'POS Challan';

  String get receiptTitle =>
      this == PosDocType.invoice ? '~~ Sales Invoice ~~' : '~~Delivery Challan ~~';
}

/// Formats a number the way the sales SPA does (`${bagQty}` in a JS template):
/// whole numbers render without a decimal part, others keep their decimals.
String formatPosNumber(num value) {
  if (value.isNaN || value.isInfinite) return '0';
  final asDouble = value.toDouble();
  if (asDouble == asDouble.roundToDouble()) {
    return asDouble.toInt().toString();
  }
  return asDouble.toString();
}

class PosSector {
  const PosSector({
    this.id,
    required this.name,
    this.description,
    this.salesPointName,
    this.sectorCode,
  });

  final int? id;
  final String name;
  final String? description;
  final String? salesPointName;
  final int? sectorCode;

  String get label => sectorCode == null ? name : '$name ($sectorCode)';

  factory PosSector.fromJson(Map<String, dynamic> json) {
    return PosSector(
      id: _toInt(json['id']),
      name: (json['name'] ?? '').toString(),
      description: _toText(json['description']),
      salesPointName: _toText(json['salesPointName']),
      sectorCode: _toInt(json['sectorCode']),
    );
  }
}

class PosChildCategory {
  const PosChildCategory({this.id, required this.name});

  final int? id;
  final String name;

  factory PosChildCategory.fromJson(Map<String, dynamic> json) {
    return PosChildCategory(
      id: _toInt(json['id']),
      name: (json['name'] ?? '').toString(),
    );
  }
}

class PosSubCategory {
  const PosSubCategory({
    this.id,
    required this.name,
    this.childCategories = const [],
  });

  final int? id;
  final String name;
  final List<PosChildCategory> childCategories;

  factory PosSubCategory.fromJson(Map<String, dynamic> json) {
    final children = json['childCategories'];
    return PosSubCategory(
      id: _toInt(json['id']),
      name: (json['name'] ?? '').toString(),
      childCategories: children is List
          ? children
              .whereType<Map>()
              .map((e) => PosChildCategory.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}

class PosCategory {
  const PosCategory({
    this.id,
    required this.name,
    this.subCategories = const [],
  });

  final int? id;
  final String name;
  final List<PosSubCategory> subCategories;

  factory PosCategory.fromJson(Map<String, dynamic> json) {
    final subs = json['subCategories'];
    return PosCategory(
      id: _toInt(json['id']),
      name: (json['name'] ?? '').toString(),
      subCategories: subs is List
          ? subs
              .whereType<Map>()
              .map((e) => PosSubCategory.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}

class PosDealer {
  const PosDealer({
    this.id,
    this.tradeName,
    this.dealerCode,
    this.zoneName,
    this.phone,
  });

  final int? id;
  final String? tradeName;
  final String? dealerCode;
  final String? zoneName;
  final String? phone;

  /// Matches `dealerName(row)` in the sales SPA:
  /// `tradeName (dealerCode) zoneName`.
  String get displayName {
    final parts = <String>[
      if (tradeName != null && tradeName!.isNotEmpty) tradeName!,
      if (dealerCode != null && dealerCode!.isNotEmpty) '(${dealerCode!})',
      if (zoneName != null && zoneName!.isNotEmpty) zoneName!,
    ];
    return parts.isEmpty ? '—' : parts.join(' ');
  }

  factory PosDealer.fromJson(Map<String, dynamic> json) {
    return PosDealer(
      id: _toInt(json['id']),
      tradeName: _toText(json['tradeName']),
      dealerCode: _toText(json['dealerCode']),
      zoneName: _toText(json['zoneName']),
      phone: _toText(json['phone']),
    );
  }
}

class PosCompany {
  const PosCompany({
    this.id,
    this.nameEn,
    this.nameBn,
    this.mobile,
    this.phone,
    this.addressEn,
    this.imageUrl,
  });

  final int? id;
  final String? nameEn;
  final String? nameBn;
  final String? mobile;
  final String? phone;
  final String? addressEn;
  final String? imageUrl;

  factory PosCompany.fromJson(Map<String, dynamic> json) {
    return PosCompany(
      id: _toInt(json['id']),
      nameEn: _toText(json['nameEn']),
      nameBn: _toText(json['nameBn']),
      mobile: _toText(json['mobile']),
      phone: _toText(json['phone']),
      addressEn: _toText(json['addressEn']),
      imageUrl: _toText(json['imageUrl']),
    );
  }
}

class PosDriver {
  const PosDriver({this.name, this.phone, this.address});

  final String? name;
  final String? phone;
  final String? address;

  factory PosDriver.fromJson(Map<String, dynamic> json) {
    return PosDriver(
      name: _toText(json['name']),
      phone: _toText(json['phone']),
      address: _toText(json['address']),
    );
  }
}

class PosOrderItem {
  const PosOrderItem({
    required this.sn,
    this.productName,
    this.shortName,
    this.unit,
    this.bagQty = 0,
    this.qty = 0,
    this.salePrice = 0,
    this.tradePrice = 0,
    this.amount = 0,
  });

  final int sn;
  final String? productName;
  final String? shortName;
  final String? unit;
  final double bagQty;
  final double qty;

  /// Money fields are retained only so the parser stays tolerant: the POS API
  /// no longer sends them (see PublicFeedPosService) and nothing in the app
  /// renders them. Do not display [salePrice], [tradePrice] or [amount] — the
  /// mobile POS must show no prices.
  final double salePrice;
  final double tradePrice;
  final double amount;

  String get displayName {
    if (shortName != null && shortName!.isNotEmpty) return shortName!;
    return productName ?? '';
  }

  /// `2 Bag (100 Kg)` — mirrors the web receipt quantity column.
  String get quantityLabel =>
      '${formatPosNumber(bagQty)} Bag (${formatPosNumber(qty)} Kg)';

  factory PosOrderItem.fromJson(Map<String, dynamic> json) {
    return PosOrderItem(
      sn: _toInt(json['sn']) ?? 0,
      productName: _toText(json['productName']),
      shortName: _toText(json['shortName']),
      unit: _toText(json['unit']),
      bagQty: _toDouble(json['bagQty']),
      qty: _toDouble(json['qty']),
      salePrice: _toDouble(json['salePrice']),
      tradePrice: _toDouble(json['tradePrice']),
      amount: _toDouble(json['amount']),
    );
  }
}

/// The money totals of a POS order.
///
/// Retained for tolerance only: the POS API no longer sends any of these
/// (see PublicFeedPosService) and the mobile POS renders none of them. The two
/// quantity totals are the fields that still arrive and still matter.
class PosOrderTotals {
  const PosOrderTotals({
    this.subTotal = 0,
    this.discount = 0,
    this.fDiscount = 0,
    this.discountTotal = 0,
    this.vatPercent = 0,
    this.totalTax = 0,
    this.othersCost = 0,
    this.transportCost = 0,
    this.depotCost = 0,
    this.advanceAmount = 0,
    this.totalAmount = 0,
    this.dueAmount = 0,
    this.returnAmount = 0,
    this.netAmount = 0,
    this.totalBagQuantity = 0,
    this.totalQuantity = 0,
    this.amountInWords = '',
  });

  final double subTotal;
  final double discount;
  final double fDiscount;
  final double discountTotal;
  final double vatPercent;
  final double totalTax;
  final double othersCost;
  final double transportCost;
  final double depotCost;
  final double advanceAmount;
  final double totalAmount;
  final double dueAmount;
  final double returnAmount;
  final double netAmount;
  final double totalBagQuantity;
  final double totalQuantity;
  final String amountInWords;

  factory PosOrderTotals.fromJson(Map<String, dynamic> json) {
    return PosOrderTotals(
      subTotal: _toDouble(json['subTotal']),
      discount: _toDouble(json['discount']),
      fDiscount: _toDouble(json['fDiscount']),
      discountTotal: _toDouble(json['discountTotal']),
      vatPercent: _toDouble(json['vatPercent']),
      totalTax: _toDouble(json['totalTax']),
      othersCost: _toDouble(json['othersCost']),
      transportCost: _toDouble(json['transportCost']),
      depotCost: _toDouble(json['depotCost']),
      advanceAmount: _toDouble(json['advanceAmount']),
      totalAmount: _toDouble(json['totalAmount']),
      dueAmount: _toDouble(json['dueAmount']),
      returnAmount: _toDouble(json['returnAmount']),
      netAmount: _toDouble(json['netAmount']),
      totalBagQuantity: _toDouble(json['totalBagQuantity']),
      totalQuantity: _toDouble(json['totalQuantity']),
      amountInWords: (json['amountInWords'] ?? '').toString(),
    );
  }
}

class PosOrderSummary {
  const PosOrderSummary({
    required this.id,
    this.feedId,
    this.status,
    this.invoiceDate,
    this.dueDate,
    this.salesPersonName,
    this.sector,
    this.dealer,
    this.items = const [],
    this.totalQuantity = 0,
    this.totalBagQuantity = 0,
    this.totalAmount = 0,
    this.dueAmount = 0,
  });

  final int id;
  final String? feedId;
  final String? status;
  final String? invoiceDate;
  final String? dueDate;
  final String? salesPersonName;
  final PosSector? sector;
  final PosDealer? dealer;
  final List<PosOrderItem> items;
  final double totalQuantity;
  final double totalBagQuantity;
  final double totalAmount;
  final double dueAmount;

  String get salesDetailsLabel => items
      .map((item) =>
          '${item.sn}. ${item.productName ?? item.displayName}: ${item.quantityLabel} * ${formatPosNumber(item.salePrice)} /-')
      .join('\n');

  factory PosOrderSummary.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    final sector = json['sector'];
    final dealer = json['dealer'];

    return PosOrderSummary(
      id: _toInt(json['id']) ?? 0,
      feedId: _toText(json['feedId']),
      status: _toText(json['status']),
      invoiceDate: _toText(json['invoiceDate']),
      dueDate: _toText(json['dueDate']),
      salesPersonName: _toText(json['salesPersonName']),
      sector: sector is Map
          ? PosSector.fromJson(Map<String, dynamic>.from(sector))
          : null,
      dealer: dealer is Map
          ? PosDealer.fromJson(Map<String, dynamic>.from(dealer))
          : null,
      items: items is List
          ? items
              .whereType<Map>()
              .map((e) => PosOrderItem.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      totalQuantity: _toDouble(json['totalQuantity']),
      totalBagQuantity: _toDouble(json['totalBagQuantity']),
      totalAmount: _toDouble(json['totalAmount']),
      dueAmount: _toDouble(json['dueAmount']),
    );
  }
}

class PosOrderDetail {
  const PosOrderDetail({
    required this.id,
    this.feedId,
    this.status,
    this.invoiceDate,
    this.dueDate,
    this.saleType,
    this.transportType,
    this.paymentStatus,
    this.deliveryAddress,
    this.billingAddress,
    this.note,
    this.company = const PosCompany(),
    this.sector,
    this.dealer,
    this.salesPersonName,
    this.driver = const PosDriver(),
    this.items = const [],
    this.totals = const PosOrderTotals(),
  });

  final int id;
  final String? feedId;
  final String? status;
  final String? invoiceDate;
  final String? dueDate;
  final String? saleType;
  final String? transportType;
  final String? paymentStatus;
  final String? deliveryAddress;
  final String? billingAddress;
  final String? note;
  final PosCompany company;
  final PosSector? sector;
  final PosDealer? dealer;
  final String? salesPersonName;
  final PosDriver driver;
  final List<PosOrderItem> items;
  final PosOrderTotals totals;

  DateTime? get invoiceDateValue => _toDate(invoiceDate);

  DateTime? get dueDateValue => _toDate(dueDate);

  factory PosOrderDetail.fromJson(Map<String, dynamic> json) {
    final order = json['order'];
    final orderMap =
        order is Map ? Map<String, dynamic>.from(order) : <String, dynamic>{};
    final company = json['company'];
    final sector = json['sector'];
    final dealer = json['dealer'];
    final driver = json['driver'];
    final items = json['items'];
    final totals = json['totals'];

    return PosOrderDetail(
      id: _toInt(orderMap['id']) ?? 0,
      feedId: _toText(orderMap['feedId']),
      status: _toText(orderMap['status']),
      invoiceDate: _toText(orderMap['invoiceDate']),
      dueDate: _toText(orderMap['dueDate']),
      saleType: _toText(orderMap['saleType']),
      transportType: _toText(orderMap['transportType']),
      paymentStatus: _toText(orderMap['paymentStatus']),
      deliveryAddress: _toText(orderMap['deliveryAddress']),
      billingAddress: _toText(orderMap['billingAddress']),
      note: _toText(orderMap['note']),
      company: company is Map
          ? PosCompany.fromJson(Map<String, dynamic>.from(company))
          : const PosCompany(),
      sector: sector is Map
          ? PosSector.fromJson(Map<String, dynamic>.from(sector))
          : null,
      dealer: dealer is Map
          ? PosDealer.fromJson(Map<String, dynamic>.from(dealer))
          : null,
      salesPersonName: _toText(json['salesPersonName']),
      driver: driver is Map
          ? PosDriver.fromJson(Map<String, dynamic>.from(driver))
          : const PosDriver(),
      items: items is List
          ? items
              .whereType<Map>()
              .map((e) => PosOrderItem.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      totals: totals is Map
          ? PosOrderTotals.fromJson(Map<String, dynamic>.from(totals))
          : const PosOrderTotals(),
    );
  }
}

class PosOrdersMeta {
  const PosOrdersMeta({
    this.currentPage = 1,
    this.lastPage = 1,
    this.perPage = 20,
    this.total = 0,
    this.approvedOrdersCount = 0,
    this.uniqueSellingDealers = 0,
    this.startDate,
    this.endDate,
  });

  final int currentPage;
  final int lastPage;
  final int perPage;
  final int total;
  final int approvedOrdersCount;
  final int uniqueSellingDealers;
  final String? startDate;
  final String? endDate;

  factory PosOrdersMeta.fromJson(Map<String, dynamic> json) {
    return PosOrdersMeta(
      currentPage: _toInt(json['current_page']) ?? 1,
      lastPage: _toInt(json['last_page']) ?? 1,
      perPage: _toInt(json['per_page']) ?? 20,
      total: _toInt(json['total']) ?? 0,
      approvedOrdersCount: _toInt(json['approved_orders_count']) ?? 0,
      uniqueSellingDealers: _toInt(json['unique_selling_dealers']) ?? 0,
      startDate: _toText(json['start_date']),
      endDate: _toText(json['end_date']),
    );
  }
}

class PosOrdersPage {
  const PosOrdersPage({this.orders = const [], this.meta = const PosOrdersMeta()});

  final List<PosOrderSummary> orders;
  final PosOrdersMeta meta;
}

int? _toInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

String? _toText(dynamic value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

DateTime? _toDate(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
