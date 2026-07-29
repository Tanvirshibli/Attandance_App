// Farm & Dealer (marketing) models for ZKTeco mobile API.

int? marketingParseInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

double? marketingParseDouble(Object? v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

String? marketingNonEmpty(Object? v) {
  final s = v?.toString().trim();
  if (s == null || s.isEmpty) return null;
  return s;
}

List<Map<String, dynamic>> marketingMapList(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}

/// Extract list payload from common API envelopes.
List<Map<String, dynamic>> marketingExtractList(
  Object? decoded, {
  List<String> keys = const ['data', 'records', 'items'],
}) {
  if (decoded is List) {
    return marketingMapList(decoded);
  }
  if (decoded is! Map) return const [];
  final map = Map<String, dynamic>.from(decoded);
  for (final key in keys) {
    final value = map[key];
    if (value is List) return marketingMapList(value);
    if (value is Map) {
      final nested = value['data'] ?? value['records'] ?? value['items'];
      if (nested is List) return marketingMapList(nested);
    }
  }
  return const [];
}

/// Extract a single object from common API envelopes.
Map<String, dynamic>? marketingExtractObject(Object? decoded) {
  if (decoded is! Map) return null;
  final map = Map<String, dynamic>.from(decoded);
  final data = map['data'];
  if (data is Map) return Map<String, dynamic>.from(data);
  if (map.containsKey('id') || map.containsKey('name')) return map;
  return map;
}

class Market {
  const Market({
    required this.id,
    required this.name,
    this.code,
    this.district,
    this.upazila,
    this.status,
  });

  final int id;
  final String name;
  final String? code;
  final String? district;
  final String? upazila;
  final String? status;

  String get displayName {
    final c = code?.trim();
    if (c != null && c.isNotEmpty) return '$name ($c)';
    return name;
  }

  factory Market.fromJson(Map<String, dynamic> json) {
    return Market(
      id: marketingParseInt(json['id']) ?? 0,
      name: (json['name'] ?? '').toString(),
      code: marketingNonEmpty(json['code']),
      district: marketingNonEmpty(json['district']),
      upazila: marketingNonEmpty(json['upazila']),
      status: marketingNonEmpty(json['status']),
    );
  }
}

class PartyProduct {
  const PartyProduct({
    this.id,
    required this.productName,
    this.categoryName,
    this.brand,
    this.unit,
    this.demandQty,
    this.stockQty,
    this.competitorPrice,
    this.competitorBrand,
    this.notes,
    this.productId,
  });

  final int? id;
  final int? productId;
  final String productName;
  final String? categoryName;
  final String? brand;
  final String? unit;
  final double? demandQty;
  final double? stockQty;
  final double? competitorPrice;
  final String? competitorBrand;
  final String? notes;

  factory PartyProduct.fromJson(Map<String, dynamic> json) {
    return PartyProduct(
      id: marketingParseInt(json['id']),
      productId: marketingParseInt(json['product_id']),
      productName:
          (json['product_name'] ?? json['productName'] ?? '').toString(),
      categoryName: marketingNonEmpty(
        json['category_name'] ?? json['categoryName'],
      ),
      brand: marketingNonEmpty(json['brand']),
      unit: marketingNonEmpty(json['unit']),
      demandQty: marketingParseDouble(
        json['demand_qty'] ?? json['demandQty'],
      ),
      stockQty: marketingParseDouble(json['stock_qty'] ?? json['stockQty']),
      competitorPrice: marketingParseDouble(
        json['competitor_price'] ?? json['competitorPrice'],
      ),
      competitorBrand: marketingNonEmpty(
        json['competitor_brand'] ?? json['competitorBrand'],
      ),
      notes: marketingNonEmpty(json['notes']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (productId != null) 'product_id': productId,
      'product_name': productName,
      if (categoryName != null) 'category_name': categoryName,
      if (brand != null) 'brand': brand,
      if (unit != null) 'unit': unit,
      if (demandQty != null) 'demand_qty': demandQty,
      if (stockQty != null) 'stock_qty': stockQty,
      if (competitorPrice != null) 'competitor_price': competitorPrice,
      if (competitorBrand != null) 'competitor_brand': competitorBrand,
      if (notes != null) 'notes': notes,
    };
  }
}

class Party {
  const Party({
    required this.id,
    required this.partyType,
    required this.name,
    this.tradeName,
    this.code,
    this.contactPerson,
    this.phone,
    this.altPhone,
    this.address,
    this.marketId,
    this.companyId,
    this.sectorId,
    this.ownerEmployeeId,
    this.lat,
    this.lng,
    this.status,
    this.notes,
    this.products = const [],
    this.attachments = const [],
    this.marketName,
  });

  final int id;
  final String partyType;
  final String name;
  final String? tradeName;
  final String? code;
  final String? contactPerson;
  final String? phone;
  final String? altPhone;
  final String? address;
  final int? marketId;
  final int? companyId;
  final int? sectorId;
  final int? ownerEmployeeId;
  final double? lat;
  final double? lng;
  final String? status;
  final String? notes;
  final List<PartyProduct> products;
  final List<Attachment> attachments;
  final String? marketName;

  bool get isFarm =>
      partyType.toLowerCase() == 'farm' ||
      partyType.toLowerCase() == 'farmer';

  String get displayName {
    final t = tradeName?.trim();
    if (t != null && t.isNotEmpty) return t;
    return name;
  }

  factory Party.fromJson(Map<String, dynamic> json) {
    final market = json['market'];
    String? marketName;
    if (market is Map) {
      marketName = marketingNonEmpty(market['name']);
    }
    return Party(
      id: marketingParseInt(json['id']) ?? 0,
      partyType: (json['party_type'] ?? json['partyType'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      tradeName: marketingNonEmpty(json['trade_name'] ?? json['tradeName']),
      code: marketingNonEmpty(json['code']),
      contactPerson: marketingNonEmpty(
        json['contact_person'] ?? json['contactPerson'],
      ),
      phone: marketingNonEmpty(json['phone']),
      altPhone: marketingNonEmpty(json['alt_phone'] ?? json['altPhone']),
      address: marketingNonEmpty(json['address']),
      marketId: marketingParseInt(json['market_id'] ?? json['marketId']),
      companyId: marketingParseInt(json['company_id'] ?? json['companyId']),
      sectorId: marketingParseInt(json['sector_id'] ?? json['sectorId']),
      ownerEmployeeId: marketingParseInt(
        json['owner_employee_id'] ?? json['ownerEmployeeId'],
      ),
      lat: marketingParseDouble(json['lat']),
      lng: marketingParseDouble(json['lng']),
      status: marketingNonEmpty(json['status']),
      notes: marketingNonEmpty(json['notes']),
      products: marketingMapList(json['products']).map(PartyProduct.fromJson).toList(),
      attachments:
          marketingMapList(json['attachments']).map(Attachment.fromJson).toList(),
      marketName: marketName ?? marketingNonEmpty(json['market_name']),
    );
  }
}

class VisitProduct {
  const VisitProduct({
    this.id,
    required this.productName,
    this.unit,
    this.observedStock,
    this.orderQty,
    this.price,
    this.notes,
    this.productId,
  });

  final int? id;
  final int? productId;
  final String productName;
  final String? unit;
  final double? observedStock;
  final double? orderQty;
  final double? price;
  final String? notes;

  factory VisitProduct.fromJson(Map<String, dynamic> json) {
    return VisitProduct(
      id: marketingParseInt(json['id']),
      productId: marketingParseInt(json['product_id']),
      productName:
          (json['product_name'] ?? json['productName'] ?? '').toString(),
      unit: marketingNonEmpty(json['unit']),
      observedStock: marketingParseDouble(
        json['observed_stock'] ?? json['observedStock'],
      ),
      orderQty: marketingParseDouble(json['order_qty'] ?? json['orderQty']),
      price: marketingParseDouble(json['price']),
      notes: marketingNonEmpty(json['notes']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (productId != null) 'product_id': productId,
      'product_name': productName,
      if (unit != null) 'unit': unit,
      if (observedStock != null) 'observed_stock': observedStock,
      if (orderQty != null) 'order_qty': orderQty,
      if (price != null) 'price': price,
      if (notes != null) 'notes': notes,
    };
  }
}

class Visit {
  const Visit({
    required this.id,
    required this.partyId,
    required this.employeeId,
    this.visitDate,
    this.checkInAt,
    this.checkOutAt,
    this.checkInLat,
    this.checkInLng,
    this.purpose,
    this.outcome,
    this.status,
    this.notes,
    this.products = const [],
    this.attachments = const [],
    this.partyName,
  });

  final int id;
  final int partyId;
  final int employeeId;
  final String? visitDate;
  final String? checkInAt;
  final String? checkOutAt;
  final double? checkInLat;
  final double? checkInLng;
  final String? purpose;
  final String? outcome;
  final String? status;
  final String? notes;
  final List<VisitProduct> products;
  final List<Attachment> attachments;
  final String? partyName;

  factory Visit.fromJson(Map<String, dynamic> json) {
    final party = json['party'];
    String? partyName;
    if (party is Map) {
      partyName = marketingNonEmpty(party['trade_name'] ?? party['name']);
    }
    return Visit(
      id: marketingParseInt(json['id']) ?? 0,
      partyId: marketingParseInt(json['party_id'] ?? json['partyId']) ?? 0,
      employeeId:
          marketingParseInt(json['employee_id'] ?? json['employeeId']) ?? 0,
      visitDate: marketingNonEmpty(json['visit_date'] ?? json['visitDate']),
      checkInAt: marketingNonEmpty(json['check_in_at'] ?? json['checkInAt']),
      checkOutAt: marketingNonEmpty(json['check_out_at'] ?? json['checkOutAt']),
      checkInLat: marketingParseDouble(
        json['check_in_lat'] ?? json['checkInLat'],
      ),
      checkInLng: marketingParseDouble(
        json['check_in_lng'] ?? json['checkInLng'],
      ),
      purpose: marketingNonEmpty(json['purpose']),
      outcome: marketingNonEmpty(json['outcome']),
      status: marketingNonEmpty(json['status']),
      notes: marketingNonEmpty(json['notes']),
      products: marketingMapList(json['products']).map(VisitProduct.fromJson).toList(),
      attachments:
          marketingMapList(json['attachments']).map(Attachment.fromJson).toList(),
      partyName: partyName ?? marketingNonEmpty(json['party_name']),
    );
  }
}

class SurveyMetric {
  const SurveyMetric({
    required this.metricKey,
    this.metricLabel,
    this.valueText,
    this.valueNumber,
    this.unit,
  });

  final String metricKey;
  final String? metricLabel;
  final String? valueText;
  final double? valueNumber;
  final String? unit;

  factory SurveyMetric.fromJson(Map<String, dynamic> json) {
    return SurveyMetric(
      metricKey: (json['metric_key'] ?? json['metricKey'] ?? '').toString(),
      metricLabel: marketingNonEmpty(
        json['metric_label'] ?? json['metricLabel'],
      ),
      valueText: marketingNonEmpty(json['value_text'] ?? json['valueText']),
      valueNumber: marketingParseDouble(
        json['value_number'] ?? json['valueNumber'],
      ),
      unit: marketingNonEmpty(json['unit']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'metric_key': metricKey,
      if (metricLabel != null) 'metric_label': metricLabel,
      if (valueText != null) 'value_text': valueText,
      if (valueNumber != null) 'value_number': valueNumber,
      if (unit != null) 'unit': unit,
    };
  }
}

class FarmSurvey {
  const FarmSurvey({
    required this.id,
    required this.partyId,
    required this.employeeId,
    this.visitId,
    this.surveyDate,
    this.farmType,
    this.birdCapacity,
    this.currentBirds,
    this.housingType,
    this.feedBrand,
    this.notes,
    this.status,
    this.metrics = const [],
    this.attachments = const [],
  });

  final int id;
  final int partyId;
  final int? visitId;
  final int employeeId;
  final String? surveyDate;
  final String? farmType;
  final double? birdCapacity;
  final double? currentBirds;
  final String? housingType;
  final String? feedBrand;
  final String? notes;
  final String? status;
  final List<SurveyMetric> metrics;
  final List<Attachment> attachments;

  factory FarmSurvey.fromJson(Map<String, dynamic> json) {
    final values = json['values'] ?? json['metrics'];
    return FarmSurvey(
      id: marketingParseInt(json['id']) ?? 0,
      partyId: marketingParseInt(json['party_id'] ?? json['partyId']) ?? 0,
      visitId: marketingParseInt(json['visit_id'] ?? json['visitId']),
      employeeId:
          marketingParseInt(json['employee_id'] ?? json['employeeId']) ?? 0,
      surveyDate: marketingNonEmpty(json['survey_date'] ?? json['surveyDate']),
      farmType: marketingNonEmpty(json['farm_type'] ?? json['farmType']),
      birdCapacity: marketingParseDouble(
        json['bird_capacity'] ?? json['birdCapacity'],
      ),
      currentBirds: marketingParseDouble(
        json['current_birds'] ?? json['currentBirds'],
      ),
      housingType: marketingNonEmpty(
        json['housing_type'] ?? json['housingType'],
      ),
      feedBrand: marketingNonEmpty(json['feed_brand'] ?? json['feedBrand']),
      notes: marketingNonEmpty(json['notes']),
      status: marketingNonEmpty(json['status']),
      metrics: marketingMapList(values).map(SurveyMetric.fromJson).toList(),
      attachments:
          marketingMapList(json['attachments']).map(Attachment.fromJson).toList(),
    );
  }
}

class Followup {
  const Followup({
    required this.id,
    required this.partyId,
    required this.employeeId,
    this.visitId,
    this.dueDate,
    this.actionType,
    this.priority,
    this.status,
    this.notes,
    this.partyName,
  });

  final int id;
  final int partyId;
  final int? visitId;
  final int employeeId;
  final String? dueDate;
  final String? actionType;
  final String? priority;
  final String? status;
  final String? notes;
  final String? partyName;

  factory Followup.fromJson(Map<String, dynamic> json) {
    final party = json['party'];
    String? partyName;
    if (party is Map) {
      partyName = marketingNonEmpty(party['trade_name'] ?? party['name']);
    }
    return Followup(
      id: marketingParseInt(json['id']) ?? 0,
      partyId: marketingParseInt(json['party_id'] ?? json['partyId']) ?? 0,
      visitId: marketingParseInt(json['visit_id'] ?? json['visitId']),
      employeeId:
          marketingParseInt(json['employee_id'] ?? json['employeeId']) ?? 0,
      dueDate: marketingNonEmpty(json['due_date'] ?? json['dueDate']),
      actionType: marketingNonEmpty(json['action_type'] ?? json['actionType']),
      priority: marketingNonEmpty(json['priority']),
      status: marketingNonEmpty(json['status']),
      notes: marketingNonEmpty(json['notes']),
      partyName: partyName ?? marketingNonEmpty(json['party_name']),
    );
  }
}

class Attachment {
  const Attachment({
    required this.id,
    this.attachableType,
    this.attachableId,
    this.url,
    this.path,
    this.originalName,
    this.mimeType,
    this.caption,
  });

  final int id;
  final String? attachableType;
  final int? attachableId;
  final String? url;
  final String? path;
  final String? originalName;
  final String? mimeType;
  final String? caption;

  String? get displayUrl {
    final u = url?.trim();
    if (u != null && u.isNotEmpty) return u;
    return null;
  }

  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      id: marketingParseInt(json['id']) ?? 0,
      attachableType: marketingNonEmpty(
        json['attachable_type'] ?? json['attachableType'],
      ),
      attachableId: marketingParseInt(
        json['attachable_id'] ?? json['attachableId'],
      ),
      url: marketingNonEmpty(json['url']),
      path: marketingNonEmpty(json['path']),
      originalName: marketingNonEmpty(
        json['original_name'] ?? json['originalName'],
      ),
      mimeType: marketingNonEmpty(json['mime_type'] ?? json['mimeType']),
      caption: marketingNonEmpty(json['caption']),
    );
  }
}
