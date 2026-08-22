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

bool? marketingParseBool(Object? v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().trim().toLowerCase();
  if (s == 'true' || s == '1' || s == 'yes') return true;
  if (s == 'false' || s == '0' || s == 'no') return false;
  return null;
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
    this.divisionName,
    this.district,
    this.upazila,
    this.unionName,
    this.villageName,
    this.address,
    this.lat,
    this.lng,
    this.status,
    this.notes,
  });

  final int id;
  final String name;
  final String? code;
  final String? divisionName;
  final String? district;
  final String? upazila;
  final String? unionName;
  final String? villageName;
  final String? address;
  final double? lat;
  final double? lng;
  final String? status;
  final String? notes;

  String get displayName {
    final c = code?.trim();
    if (c != null && c.isNotEmpty) return '$name ($c)';
    return name;
  }

  String get locationLine {
    final parts = [
      villageName,
      unionName,
      upazila,
      district,
      divisionName,
    ].whereType<String>().where((e) => e.isNotEmpty);
    return parts.join(', ');
  }

  factory Market.fromJson(Map<String, dynamic> json) {
    return Market(
      id: marketingParseInt(json['id']) ?? 0,
      name: (json['name'] ?? '').toString(),
      code: marketingNonEmpty(json['code']),
      divisionName: marketingNonEmpty(
        json['divisionName'] ?? json['division_name'],
      ),
      district: marketingNonEmpty(json['district']),
      upazila: marketingNonEmpty(json['upazila']),
      unionName: marketingNonEmpty(json['unionName'] ?? json['union_name']),
      villageName: marketingNonEmpty(
        json['villageName'] ?? json['village_name'],
      ),
      address: marketingNonEmpty(json['address']),
      lat: marketingParseDouble(json['lat']),
      lng: marketingParseDouble(json['lng']),
      status: marketingNonEmpty(json['status']),
      notes: marketingNonEmpty(json['notes']),
    );
  }

  @override
  bool operator ==(Object other) => other is Market && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class PartyProduct {
  const PartyProduct({
    this.id,
    required this.productName,
    this.categoryName,
    this.brand,
    this.brandName,
    this.unit,
    this.demandQty,
    this.stockQty,
    this.competitorPrice,
    this.competitorBrand,
    this.competitorCompany,
    this.relationType,
    this.monthlyQuantity,
    this.currentStock,
    this.unitId,
    this.unitPrice,
    this.isOurProduct,
    this.notes,
    this.productId,
  });

  final int? id;
  final int? productId;
  final String productName;
  final String? categoryName;
  final String? brand;
  final String? brandName;
  final String? unit;
  final double? demandQty;
  final double? stockQty;
  final double? competitorPrice;
  final String? competitorBrand;
  final String? competitorCompany;
  final String? relationType;
  final double? monthlyQuantity;
  final double? currentStock;
  final int? unitId;
  final double? unitPrice;
  final bool? isOurProduct;
  final String? notes;

  factory PartyProduct.fromJson(Map<String, dynamic> json) {
    return PartyProduct(
      id: marketingParseInt(json['id']),
      productId: marketingParseInt(json['productId'] ?? json['product_id']),
      productName:
          (json['productName'] ?? json['product_name'] ?? '').toString(),
      categoryName: marketingNonEmpty(
        json['categoryName'] ?? json['category_name'],
      ),
      brand: marketingNonEmpty(json['brand']),
      brandName: marketingNonEmpty(json['brandName'] ?? json['brand_name']),
      unit: marketingNonEmpty(json['unit']),
      demandQty: marketingParseDouble(
        json['demandQty'] ?? json['demand_qty'],
      ),
      stockQty: marketingParseDouble(json['stockQty'] ?? json['stock_qty']),
      competitorPrice: marketingParseDouble(
        json['competitorPrice'] ?? json['competitor_price'],
      ),
      competitorBrand: marketingNonEmpty(
        json['competitorBrand'] ?? json['competitor_brand'],
      ),
      competitorCompany: marketingNonEmpty(
        json['competitorCompany'] ?? json['competitor_company'],
      ),
      relationType: marketingNonEmpty(
        json['relationType'] ?? json['relation_type'],
      ),
      monthlyQuantity: marketingParseDouble(
        json['monthlyQuantity'] ?? json['monthly_quantity'],
      ),
      currentStock: marketingParseDouble(
        json['currentStock'] ?? json['current_stock'],
      ),
      unitId: marketingParseInt(json['unitId'] ?? json['unit_id']),
      unitPrice: marketingParseDouble(json['unitPrice'] ?? json['unit_price']),
      isOurProduct: marketingParseBool(
        json['isOurProduct'] ?? json['is_our_product'],
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
      if (brandName != null) 'brand_name': brandName,
      if (unit != null) 'unit': unit,
      if (demandQty != null) 'demand_qty': demandQty,
      if (stockQty != null) 'stock_qty': stockQty,
      if (competitorPrice != null) 'competitor_price': competitorPrice,
      if (competitorBrand != null) 'competitor_brand': competitorBrand,
      if (competitorCompany != null) 'competitor_company': competitorCompany,
      if (relationType != null) 'relation_type': relationType,
      if (monthlyQuantity != null) 'monthly_quantity': monthlyQuantity,
      if (currentStock != null) 'current_stock': currentStock,
      if (unitId != null) 'unit_id': unitId,
      if (unitPrice != null) 'unit_price': unitPrice,
      if (isOurProduct != null) 'is_our_product': isOurProduct,
      if (notes != null) 'notes': notes,
    };
  }
}

class Party {
  const Party({
    required this.id,
    required this.partyType,
    required this.name,
    this.publicId,
    this.tradeName,
    this.code,
    this.contactPerson,
    this.ownerName,
    this.phone,
    this.altPhone,
    this.email,
    this.nidNo,
    this.tradeLicenseNo,
    this.address,
    this.businessYears,
    this.farmType,
    this.capacity,
    this.capacityUnitId,
    this.creditLimit,
    this.paymentMode,
    this.leadStatus,
    this.marketId,
    this.parentPartyId,
    this.existingDealerId,
    this.companyId,
    this.sectorId,
    this.ownerEmployeeId,
    this.createdByEmployeeId,
    this.lat,
    this.lng,
    this.status,
    this.notes,
    this.products = const [],
    this.attachments = const [],
    this.marketName,
    this.parentPartyName,
    this.parentPartyPhone,
    this.parentPartyAddress,
  });

  final int id;
  final String? publicId;
  final String partyType;
  final String name;
  final String? tradeName;
  final String? code;
  final String? contactPerson;
  final String? ownerName;
  final String? phone;
  final String? altPhone;
  final String? email;
  final String? nidNo;
  final String? tradeLicenseNo;
  final String? address;
  final double? businessYears;
  final String? farmType;
  final double? capacity;
  final int? capacityUnitId;
  final double? creditLimit;
  final String? paymentMode;
  final String? leadStatus;
  final int? marketId;
  final int? parentPartyId;
  final int? existingDealerId;
  final int? companyId;
  final int? sectorId;
  final int? ownerEmployeeId;
  final int? createdByEmployeeId;
  final double? lat;
  final double? lng;
  final String? status;
  final String? notes;
  final List<PartyProduct> products;
  final List<Attachment> attachments;
  final String? marketName;
  final String? parentPartyName;
  final String? parentPartyPhone;
  final String? parentPartyAddress;

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
      publicId: marketingNonEmpty(json['publicId'] ?? json['public_id']),
      partyType: (json['partyType'] ?? json['party_type'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      tradeName: marketingNonEmpty(json['tradeName'] ?? json['trade_name']),
      code: marketingNonEmpty(json['code']),
      contactPerson: marketingNonEmpty(
        json['contactPerson'] ?? json['contact_person'],
      ),
      ownerName: marketingNonEmpty(json['ownerName'] ?? json['owner_name']),
      phone: marketingNonEmpty(json['phone']),
      altPhone: marketingNonEmpty(json['altPhone'] ?? json['alt_phone']),
      email: marketingNonEmpty(json['email']),
      nidNo: marketingNonEmpty(json['nidNo'] ?? json['nid_no']),
      tradeLicenseNo: marketingNonEmpty(
        json['tradeLicenseNo'] ?? json['trade_license_no'],
      ),
      address: marketingNonEmpty(json['address']),
      businessYears: marketingParseDouble(
        json['businessYears'] ?? json['business_years'],
      ),
      farmType: marketingNonEmpty(json['farmType'] ?? json['farm_type']),
      capacity: marketingParseDouble(json['capacity']),
      capacityUnitId: marketingParseInt(
        json['capacityUnitId'] ?? json['capacity_unit_id'],
      ),
      creditLimit: marketingParseDouble(
        json['creditLimit'] ?? json['credit_limit'],
      ),
      paymentMode: marketingNonEmpty(
        json['paymentMode'] ?? json['payment_mode'],
      ),
      leadStatus: marketingNonEmpty(json['leadStatus'] ?? json['lead_status']),
      marketId: marketingParseInt(json['marketId'] ?? json['market_id']),
      parentPartyId: marketingParseInt(
        json['parentPartyId'] ?? json['parent_party_id'],
      ),
      existingDealerId: marketingParseInt(
        json['existingDealerId'] ?? json['existing_dealer_id'],
      ),
      companyId: marketingParseInt(json['companyId'] ?? json['company_id']),
      sectorId: marketingParseInt(json['sectorId'] ?? json['sector_id']),
      ownerEmployeeId: marketingParseInt(
        json['ownerEmployeeId'] ?? json['owner_employee_id'],
      ),
      createdByEmployeeId: marketingParseInt(
        json['createdByEmployeeId'] ?? json['created_by_employee_id'],
      ),
      lat: marketingParseDouble(json['lat']),
      lng: marketingParseDouble(json['lng']),
      status: marketingNonEmpty(json['status']),
      notes: marketingNonEmpty(json['notes']),
      products:
          marketingMapList(json['products']).map(PartyProduct.fromJson).toList(),
      attachments: marketingMapList(json['attachments'])
          .map(Attachment.fromJson)
          .toList(),
      marketName: marketName ??
          marketingNonEmpty(json['marketName'] ?? json['market_name']),
      parentPartyName: marketingNonEmpty(
        json['parentPartyName'] ?? json['parent_party_name'],
      ),
      parentPartyPhone: marketingNonEmpty(
        json['parentPartyPhone'] ?? json['parent_party_phone'],
      ),
      parentPartyAddress: marketingNonEmpty(
        json['parentPartyAddress'] ?? json['parent_party_address'],
      ),
    );
  }

  @override
  bool operator ==(Object other) => other is Party && other.id == id;

  @override
  int get hashCode => id.hashCode;
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
    this.observationType,
    this.brandName,
    this.competitorCompany,
    this.quantity,
    this.demandQuantity,
    this.stockQuantity,
    this.unitId,
    this.unitPrice,
    this.amount,
  });

  final int? id;
  final int? productId;
  final String productName;
  final String? unit;
  final double? observedStock;
  final double? orderQty;
  final double? price;
  final String? notes;
  final String? observationType;
  final String? brandName;
  final String? competitorCompany;
  final double? quantity;
  final double? demandQuantity;
  final double? stockQuantity;
  final int? unitId;
  final double? unitPrice;
  final double? amount;

  factory VisitProduct.fromJson(Map<String, dynamic> json) {
    return VisitProduct(
      id: marketingParseInt(json['id']),
      productId: marketingParseInt(json['productId'] ?? json['product_id']),
      productName:
          (json['productName'] ?? json['product_name'] ?? '').toString(),
      unit: marketingNonEmpty(json['unit']),
      observedStock: marketingParseDouble(
        json['observedStock'] ?? json['observed_stock'],
      ),
      orderQty: marketingParseDouble(json['orderQty'] ?? json['order_qty']),
      price: marketingParseDouble(json['price']),
      notes: marketingNonEmpty(json['notes']),
      observationType: marketingNonEmpty(
        json['observationType'] ?? json['observation_type'],
      ),
      brandName: marketingNonEmpty(json['brandName'] ?? json['brand_name']),
      competitorCompany: marketingNonEmpty(
        json['competitorCompany'] ?? json['competitor_company'],
      ),
      quantity: marketingParseDouble(json['quantity']),
      demandQuantity: marketingParseDouble(
        json['demandQuantity'] ?? json['demand_quantity'],
      ),
      stockQuantity: marketingParseDouble(
        json['stockQuantity'] ?? json['stock_quantity'],
      ),
      unitId: marketingParseInt(json['unitId'] ?? json['unit_id']),
      unitPrice: marketingParseDouble(json['unitPrice'] ?? json['unit_price']),
      amount: marketingParseDouble(json['amount']),
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
      if (observationType != null) 'observation_type': observationType,
      if (brandName != null) 'brand_name': brandName,
      if (competitorCompany != null) 'competitor_company': competitorCompany,
      if (quantity != null) 'quantity': quantity,
      if (demandQuantity != null) 'demand_quantity': demandQuantity,
      if (stockQuantity != null) 'stock_quantity': stockQuantity,
      if (unitId != null) 'unit_id': unitId,
      if (unitPrice != null) 'unit_price': unitPrice,
      if (amount != null) 'amount': amount,
    };
  }
}

class Visit {
  const Visit({
    required this.id,
    required this.partyId,
    required this.employeeId,
    this.publicId,
    this.clientUuid,
    this.visitNo,
    this.marketId,
    this.companyId,
    this.sectorId,
    this.visitDate,
    this.visitType,
    this.checkInAt,
    this.checkOutAt,
    this.checkInLat,
    this.checkInLng,
    this.checkOutLat,
    this.checkOutLng,
    this.geoVerified,
    this.purpose,
    this.objective,
    this.findings,
    this.result,
    this.outcome,
    this.nextPlan,
    this.nextVisitDate,
    this.orderAmount,
    this.collectionAmount,
    this.status,
    this.notes,
    this.products = const [],
    this.attachments = const [],
    this.partyName,
  });

  final int id;
  final String? publicId;
  final String? clientUuid;
  final String? visitNo;
  final int partyId;
  final int employeeId;
  final int? marketId;
  final int? companyId;
  final int? sectorId;
  final String? visitDate;
  final String? visitType;
  final String? checkInAt;
  final String? checkOutAt;
  final double? checkInLat;
  final double? checkInLng;
  final double? checkOutLat;
  final double? checkOutLng;
  final bool? geoVerified;
  final String? purpose;
  final String? objective;
  final String? findings;
  final String? result;
  final String? outcome;
  final String? nextPlan;
  final String? nextVisitDate;
  final double? orderAmount;
  final double? collectionAmount;
  final String? status;
  final String? notes;
  final List<VisitProduct> products;
  final List<Attachment> attachments;
  final String? partyName;

  factory Visit.fromJson(Map<String, dynamic> json) {
    final party = json['party'];
    String? partyName;
    if (party is Map) {
      partyName = marketingNonEmpty(party['tradeName'] ??
          party['trade_name'] ??
          party['name']);
    }
    return Visit(
      id: marketingParseInt(json['id']) ?? 0,
      publicId: marketingNonEmpty(json['publicId'] ?? json['public_id']),
      clientUuid: marketingNonEmpty(json['clientUuid'] ?? json['client_uuid']),
      visitNo: marketingNonEmpty(json['visitNo'] ?? json['visit_no']),
      partyId: marketingParseInt(json['partyId'] ?? json['party_id']) ?? 0,
      employeeId:
          marketingParseInt(json['employeeId'] ?? json['employee_id']) ?? 0,
      marketId: marketingParseInt(json['marketId'] ?? json['market_id']),
      companyId: marketingParseInt(json['companyId'] ?? json['company_id']),
      sectorId: marketingParseInt(json['sectorId'] ?? json['sector_id']),
      visitDate: marketingNonEmpty(json['visitDate'] ?? json['visit_date']),
      visitType: marketingNonEmpty(json['visitType'] ?? json['visit_type']),
      checkInAt: marketingNonEmpty(json['checkInAt'] ?? json['check_in_at']),
      checkOutAt: marketingNonEmpty(json['checkOutAt'] ?? json['check_out_at']),
      checkInLat: marketingParseDouble(
        json['checkInLat'] ?? json['check_in_lat'],
      ),
      checkInLng: marketingParseDouble(
        json['checkInLng'] ?? json['check_in_lng'],
      ),
      checkOutLat: marketingParseDouble(
        json['checkOutLat'] ?? json['check_out_lat'],
      ),
      checkOutLng: marketingParseDouble(
        json['checkOutLng'] ?? json['check_out_lng'],
      ),
      geoVerified: marketingParseBool(
        json['geoVerified'] ?? json['geo_verified'],
      ),
      purpose: marketingNonEmpty(json['purpose']),
      objective: marketingNonEmpty(json['objective']),
      findings: marketingNonEmpty(json['findings']),
      result: marketingNonEmpty(json['result']),
      outcome: marketingNonEmpty(json['outcome']),
      nextPlan: marketingNonEmpty(json['nextPlan'] ?? json['next_plan']),
      nextVisitDate: marketingNonEmpty(
        json['nextVisitDate'] ?? json['next_visit_date'],
      ),
      orderAmount: marketingParseDouble(
        json['orderAmount'] ?? json['order_amount'],
      ),
      collectionAmount: marketingParseDouble(
        json['collectionAmount'] ?? json['collection_amount'],
      ),
      status: marketingNonEmpty(json['status']),
      notes: marketingNonEmpty(json['notes']),
      products:
          marketingMapList(json['products']).map(VisitProduct.fromJson).toList(),
      attachments: marketingMapList(json['attachments'])
          .map(Attachment.fromJson)
          .toList(),
      partyName: partyName ??
          marketingNonEmpty(json['partyName'] ?? json['party_name']),
    );
  }

  String get displayName {
    final no = visitNo?.trim();
    final type = (visitType ?? 'visit').replaceAll('_', ' ');
    final date = visitDate ?? '';
    final head = (no != null && no.isNotEmpty) ? no : '#$id';
    return [head, type, date].where((e) => e.isNotEmpty).join(' · ');
  }

  @override
  bool operator ==(Object other) => other is Visit && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class SurveyMetric {
  const SurveyMetric({
    required this.metricKey,
    this.metricLabel,
    this.valueText,
    this.valueNumber,
    this.unit,
    this.booleanValue,
    this.dateValue,
    this.remarks,
  });

  final String metricKey;
  final String? metricLabel;
  final String? valueText;
  final double? valueNumber;
  final String? unit;
  final bool? booleanValue;
  final String? dateValue;
  final String? remarks;

  factory SurveyMetric.fromJson(Map<String, dynamic> json) {
    return SurveyMetric(
      metricKey: (json['metricKey'] ??
              json['metric_key'] ??
              json['metricCode'] ??
              json['metric_code'] ??
              '')
          .toString(),
      metricLabel: marketingNonEmpty(
        json['metricLabel'] ?? json['metric_label'],
      ),
      valueText: marketingNonEmpty(json['valueText'] ?? json['value_text']),
      valueNumber: marketingParseDouble(
        json['valueNumber'] ?? json['value_number'],
      ),
      unit: marketingNonEmpty(json['unit']),
      booleanValue: marketingParseBool(
        json['booleanValue'] ?? json['boolean_value'],
      ),
      dateValue: marketingNonEmpty(json['dateValue'] ?? json['date_value']),
      remarks: marketingNonEmpty(json['remarks']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'metric_key': metricKey,
      if (metricLabel != null) 'metric_label': metricLabel,
      if (valueText != null) 'value_text': valueText,
      if (valueNumber != null) 'value_number': valueNumber,
      if (unit != null) 'unit': unit,
      if (booleanValue != null) 'boolean_value': booleanValue,
      if (dateValue != null) 'date_value': dateValue,
      if (remarks != null) 'remarks': remarks,
    };
  }
}

class FarmSurvey {
  const FarmSurvey({
    required this.id,
    required this.partyId,
    required this.employeeId,
    this.publicId,
    this.visitId,
    this.dealerPartyId,
    this.dealerPartyName,
    this.partyName,
    this.surveyDate,
    this.surveyType,
    this.hatchDate,
    this.receivingDate,
    this.receivingTime,
    this.breed,
    this.docCompany,
    this.feedCompany,
    this.farmingYears,
    this.farmType,
    this.ageDays,
    this.quantity,
    this.quantityUnitId,
    this.chicksProductId,
    this.mortalityQuantity,
    this.totalMortality,
    this.presentMortality,
    this.mortalityPercent,
    this.restOfBirds,
    this.feedProductId,
    this.chicksBrand,
    this.birdCapacity,
    this.currentBirds,
    this.housingType,
    this.shedDesign,
    this.curtainType,
    this.floorType,
    this.feederQty,
    this.drinkerQty,
    this.avgTemperature,
    this.spaceNote,
    this.feedBrand,
    this.totalFeedIntakeKg,
    this.avgFeedIntakeKg,
    this.productionPercent,
    this.fcr,
    this.avgBodyWeightKg,
    this.totalBodyWeightKg,
    this.bagWeightKg,
    this.uniformityPercent,
    this.biosecurityRating,
    this.managementRating,
    this.technicalSupportRating,
    this.economicSolvencyRating,
    this.diseasePresent,
    this.diseaseDetails,
    this.problems,
    this.recommendation,
    this.notes,
    this.comments,
    this.territory,
    this.zone,
    this.status,
    this.metrics = const [],
    this.attachments = const [],
    this.extraData,
  });

  final int id;
  final String? publicId;
  final int partyId;
  final String? partyName;
  final int? visitId;
  final int? dealerPartyId;
  final String? dealerPartyName;
  final int employeeId;
  final String? surveyDate;
  final String? surveyType;
  final String? hatchDate;
  final String? receivingDate;
  final String? receivingTime;
  final String? breed;
  final String? docCompany;
  final String? feedCompany;
  final double? farmingYears;
  final String? farmType;
  final int? ageDays;
  final double? quantity;
  final int? quantityUnitId;
  final int? chicksProductId;
  final int? feedProductId;
  final double? mortalityQuantity;
  final double? totalMortality;
  final double? presentMortality;
  final double? mortalityPercent;
  final double? restOfBirds;
  final String? chicksBrand;
  final double? birdCapacity;
  final double? currentBirds;
  final String? housingType;
  final String? shedDesign;
  final String? curtainType;
  final String? floorType;
  final double? feederQty;
  final double? drinkerQty;
  final double? avgTemperature;
  final String? spaceNote;
  final String? feedBrand;
  final double? totalFeedIntakeKg;
  final double? avgFeedIntakeKg;
  final double? productionPercent;
  final double? fcr;
  final double? avgBodyWeightKg;
  final double? totalBodyWeightKg;
  final double? bagWeightKg;
  final double? uniformityPercent;
  final int? biosecurityRating;
  final int? managementRating;
  final int? technicalSupportRating;
  final int? economicSolvencyRating;
  final bool? diseasePresent;
  final String? diseaseDetails;
  final String? problems;
  final String? recommendation;
  final String? notes;
  final String? comments;
  final String? territory;
  final String? zone;
  final String? status;
  final List<SurveyMetric> metrics;
  final List<Attachment> attachments;
  final Map<String, dynamic>? extraData;

  String get displayTitle {
    final date = surveyDate ?? '';
    final breedLabel = breed?.trim();
    if (breedLabel != null && breedLabel.isNotEmpty) {
      return [date, breedLabel].where((e) => e.isNotEmpty).join(' · ');
    }
    return date.isNotEmpty ? date : 'Farm visit report';
  }

  factory FarmSurvey.fromJson(Map<String, dynamic> json) {
    final values = json['values'] ?? json['metrics'];
    return FarmSurvey(
      id: marketingParseInt(json['id']) ?? 0,
      publicId: marketingNonEmpty(json['publicId'] ?? json['public_id']),
      partyId: marketingParseInt(json['partyId'] ?? json['party_id']) ?? 0,
      partyName: marketingNonEmpty(json['partyName'] ?? json['party_name']),
      visitId: marketingParseInt(json['visitId'] ?? json['visit_id']),
      dealerPartyId: marketingParseInt(
        json['dealerPartyId'] ?? json['dealer_party_id'],
      ),
      dealerPartyName: marketingNonEmpty(
        json['dealerPartyName'] ?? json['dealer_party_name'],
      ),
      employeeId:
          marketingParseInt(json['employeeId'] ?? json['employee_id']) ?? 0,
      surveyDate: marketingNonEmpty(json['surveyDate'] ?? json['survey_date']),
      surveyType: marketingNonEmpty(json['surveyType'] ?? json['survey_type']),
      hatchDate: marketingNonEmpty(json['hatchDate'] ?? json['hatch_date']),
      receivingDate: marketingNonEmpty(
        json['receivingDate'] ?? json['receiving_date'],
      ),
      receivingTime: marketingNonEmpty(
        json['receivingTime'] ?? json['receiving_time'],
      ),
      breed: marketingNonEmpty(json['breed']),
      docCompany: marketingNonEmpty(json['docCompany'] ?? json['doc_company']),
      feedCompany: marketingNonEmpty(
        json['feedCompany'] ?? json['feed_company'],
      ),
      farmingYears: marketingParseDouble(
        json['farmingYears'] ?? json['farming_years'],
      ),
      farmType: marketingNonEmpty(json['farmType'] ?? json['farm_type']),
      ageDays: marketingParseInt(json['ageDays'] ?? json['age_days']),
      quantity: marketingParseDouble(json['quantity']),
      quantityUnitId: marketingParseInt(
        json['quantityUnitId'] ?? json['quantity_unit_id'],
      ),
      chicksProductId: marketingParseInt(
        json['chicksProductId'] ?? json['chicks_product_id'],
      ),
      feedProductId: marketingParseInt(
        json['feedProductId'] ?? json['feed_product_id'],
      ),
      mortalityQuantity: marketingParseDouble(
        json['mortalityQuantity'] ?? json['mortality_quantity'],
      ),
      totalMortality: marketingParseDouble(
        json['totalMortality'] ?? json['total_mortality'],
      ),
      presentMortality: marketingParseDouble(
        json['presentMortality'] ?? json['present_mortality'],
      ),
      mortalityPercent: marketingParseDouble(
        json['mortalityPercent'] ?? json['mortality_percent'],
      ),
      restOfBirds: marketingParseDouble(
        json['restOfBirds'] ?? json['rest_of_birds'],
      ),
      chicksBrand: marketingNonEmpty(
        json['chicksBrand'] ?? json['chicks_brand'],
      ),
      birdCapacity: marketingParseDouble(
        json['birdCapacity'] ?? json['bird_capacity'],
      ),
      currentBirds: marketingParseDouble(
        json['currentBirds'] ?? json['current_birds'],
      ),
      housingType: marketingNonEmpty(
        json['housingType'] ?? json['housing_type'],
      ),
      shedDesign: marketingNonEmpty(json['shedDesign'] ?? json['shed_design']),
      curtainType: marketingNonEmpty(
        json['curtainType'] ?? json['curtain_type'],
      ),
      floorType: marketingNonEmpty(json['floorType'] ?? json['floor_type']),
      feederQty: marketingParseDouble(json['feederQty'] ?? json['feeder_qty']),
      drinkerQty: marketingParseDouble(
        json['drinkerQty'] ?? json['drinker_qty'],
      ),
      avgTemperature: marketingParseDouble(
        json['avgTemperature'] ?? json['avg_temperature'],
      ),
      spaceNote: marketingNonEmpty(json['spaceNote'] ?? json['space_note']),
      feedBrand: marketingNonEmpty(json['feedBrand'] ?? json['feed_brand']),
      totalFeedIntakeKg: marketingParseDouble(
        json['totalFeedIntakeKg'] ?? json['total_feed_intake_kg'],
      ),
      avgFeedIntakeKg: marketingParseDouble(
        json['avgFeedIntakeKg'] ?? json['avg_feed_intake_kg'],
      ),
      productionPercent: marketingParseDouble(
        json['productionPercent'] ?? json['production_percent'],
      ),
      fcr: marketingParseDouble(json['fcr']),
      avgBodyWeightKg: marketingParseDouble(
        json['avgBodyWeightKg'] ?? json['avg_body_weight_kg'],
      ),
      totalBodyWeightKg: marketingParseDouble(
        json['totalBodyWeightKg'] ?? json['total_body_weight_kg'],
      ),
      bagWeightKg: marketingParseDouble(
        json['bagWeightKg'] ?? json['bag_weight_kg'],
      ),
      uniformityPercent: marketingParseDouble(
        json['uniformityPercent'] ?? json['uniformity_percent'],
      ),
      biosecurityRating: marketingParseInt(
        json['biosecurityRating'] ?? json['biosecurity_rating'],
      ),
      managementRating: marketingParseInt(
        json['managementRating'] ?? json['management_rating'],
      ),
      technicalSupportRating: marketingParseInt(
        json['technicalSupportRating'] ?? json['technical_support_rating'],
      ),
      economicSolvencyRating: marketingParseInt(
        json['economicSolvencyRating'] ?? json['economic_solvency_rating'],
      ),
      diseasePresent: marketingParseBool(
        json['diseasePresent'] ?? json['disease_present'],
      ),
      diseaseDetails: marketingNonEmpty(
        json['diseaseDetails'] ?? json['disease_details'],
      ),
      problems: marketingNonEmpty(json['problems']),
      recommendation: marketingNonEmpty(json['recommendation']),
      notes: marketingNonEmpty(json['notes']),
      comments: marketingNonEmpty(json['comments']),
      territory: marketingNonEmpty(json['territory']),
      zone: marketingNonEmpty(json['zone']),
      status: marketingNonEmpty(json['status']),
      metrics: marketingMapList(values).map(SurveyMetric.fromJson).toList(),
      attachments: marketingMapList(json['attachments'])
          .map(Attachment.fromJson)
          .toList(),
      extraData: json['extraData'] is Map
          ? Map<String, dynamic>.from(json['extraData'] as Map)
          : json['extra_data'] is Map
              ? Map<String, dynamic>.from(json['extra_data'] as Map)
              : null,
    );
  }
}

class Followup {
  const Followup({
    required this.id,
    required this.partyId,
    required this.employeeId,
    this.visitId,
    this.assignedToEmployeeId,
    this.dueDate,
    this.actionType,
    this.title,
    this.description,
    this.priority,
    this.status,
    this.notes,
    this.completionNote,
    this.completedAt,
    this.partyName,
  });

  final int id;
  final int partyId;
  final int? visitId;
  final int? assignedToEmployeeId;
  final int employeeId;
  final String? dueDate;
  final String? actionType;
  final String? title;
  final String? description;
  final String? priority;
  final String? status;
  final String? notes;
  final String? completionNote;
  final String? completedAt;
  final String? partyName;

  String get displayTitle {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    return actionType ?? 'Follow-up';
  }

  factory Followup.fromJson(Map<String, dynamic> json) {
    final party = json['party'];
    String? partyName;
    if (party is Map) {
      partyName = marketingNonEmpty(party['tradeName'] ??
          party['trade_name'] ??
          party['name']);
    }
    return Followup(
      id: marketingParseInt(json['id']) ?? 0,
      partyId: marketingParseInt(json['partyId'] ?? json['party_id']) ?? 0,
      visitId: marketingParseInt(json['visitId'] ?? json['visit_id']),
      assignedToEmployeeId: marketingParseInt(
        json['assignedToEmployeeId'] ?? json['assigned_to_employee_id'],
      ),
      employeeId:
          marketingParseInt(json['employeeId'] ?? json['employee_id']) ?? 0,
      dueDate: marketingNonEmpty(json['dueDate'] ?? json['due_date']),
      actionType: marketingNonEmpty(json['actionType'] ?? json['action_type']),
      title: marketingNonEmpty(json['title']),
      description: marketingNonEmpty(json['description']),
      priority: marketingNonEmpty(json['priority']),
      status: marketingNonEmpty(json['status']),
      notes: marketingNonEmpty(json['notes']),
      completionNote: marketingNonEmpty(
        json['completionNote'] ?? json['completion_note'],
      ),
      completedAt: marketingNonEmpty(
        json['completedAt'] ?? json['completed_at'],
      ),
      partyName: partyName ??
          marketingNonEmpty(json['partyName'] ?? json['party_name']),
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
    this.fileType,
  });

  final int id;
  final String? attachableType;
  final int? attachableId;
  final String? url;
  final String? path;
  final String? originalName;
  final String? mimeType;
  final String? caption;
  final String? fileType;

  String? get displayUrl {
    final u = url?.trim();
    if (u != null && u.isNotEmpty) return u;
    return null;
  }

  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      id: marketingParseInt(json['id']) ?? 0,
      attachableType: marketingNonEmpty(
        json['attachableType'] ?? json['attachable_type'],
      ),
      attachableId: marketingParseInt(
        json['attachableId'] ?? json['attachable_id'],
      ),
      url: marketingNonEmpty(json['url']),
      path: marketingNonEmpty(json['path']),
      originalName: marketingNonEmpty(
        json['originalName'] ?? json['original_name'],
      ),
      mimeType: marketingNonEmpty(json['mimeType'] ?? json['mime_type']),
      caption: marketingNonEmpty(json['caption']),
      fileType: marketingNonEmpty(json['fileType'] ?? json['file_type']),
    );
  }
}
