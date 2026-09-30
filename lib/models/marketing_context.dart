import 'dealer_list_models.dart';

/// The zone / company / sector / market context the backend resolves for the
/// logged-in employee.
///
/// This is what replaced the client-side name guess. HRM exposes only a single
/// free-text `sector` name for an employee and no company at all, so matching
/// that string against two independent Sales lists could not work — which is
/// why the forms used to render "Unresolved from your profile". The relation is
/// resolved server-side, from the synced marketing org master, and arrives here
/// as ids and names.
///
/// Every field is nullable and independently resolved: a form shows what it got
/// and omits the rest from the payload rather than inventing an id.
class MarketingContext {
  const MarketingContext({
    this.zone,
    this.company,
    this.sector,
    this.sectors = const [],
    this.markets = const [],
  });

  const MarketingContext.empty() : this();

  final MarketingContextZone? zone;
  final MarketingContextCompany? company;
  final MarketingContextSector? sector;
  final List<MarketingContextSector> sectors;
  final List<MarketingContextMarket> markets;

  bool get hasZone => zone != null;

  /// True when the zone resolved but the company did not. Worth distinguishing
  /// from a fully empty scope: the officer's zone is set, so an admin can fix
  /// the sector rather than the whole profile.
  bool get hasZoneWithoutCompany => zone != null && company == null;

  factory MarketingContext.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const MarketingContext.empty();
    return MarketingContext(
      zone: _object(json['zone']) == null
          ? null
          : MarketingContextZone.fromJson(_object(json['zone'])!),
      company: _object(json['company']) == null
          ? null
          : MarketingContextCompany.fromJson(_object(json['company'])!),
      sector: _object(json['sector']) == null
          ? null
          : MarketingContextSector.fromJson(_object(json['sector'])!),
      sectors: _list(json['sectors'])
          .map((e) => MarketingContextSector.fromJson(e))
          .toList(),
      markets: _list(json['markets'])
          .map((e) => MarketingContextMarket.fromJson(e))
          .toList(),
    );
  }
}

class MarketingContextZone {
  const MarketingContextZone({required this.id, required this.name});

  final int id;
  final String name;

  factory MarketingContextZone.fromJson(Map<String, dynamic> json) {
    return MarketingContextZone(
      id: _asInt(json['id']),
      name: json['name']?.toString() ?? '',
    );
  }
}

class MarketingContextCompany {
  const MarketingContextCompany({required this.id, required this.name});

  final int id;
  final String name;

  factory MarketingContextCompany.fromJson(Map<String, dynamic> json) {
    return MarketingContextCompany(
      id: _asInt(json['id']),
      name: json['name']?.toString() ?? '',
    );
  }
}

class MarketingContextSector {
  const MarketingContextSector({
    required this.id,
    required this.name,
    this.companyId,
    this.companyName,
  });

  final int id;
  final String name;
  final int? companyId;
  final String? companyName;

  factory MarketingContextSector.fromJson(Map<String, dynamic> json) {
    return MarketingContextSector(
      id: _asInt(json['id']),
      name: json['name']?.toString() ?? '',
      companyId: _asIntOrNull(json['companyId']),
      companyName: json['companyName']?.toString(),
    );
  }
}

class MarketingContextMarket {
  const MarketingContextMarket({
    required this.id,
    required this.name,
    this.district,
    this.companyName,
    this.sectorName,
  });

  final int id;
  final String name;
  final String? district;
  final String? companyName;
  final String? sectorName;

  String get subtitle => [
        companyName,
        sectorName,
        district,
      ].where((part) => part != null && part.trim().isNotEmpty).join(' · ');

  factory MarketingContextMarket.fromJson(Map<String, dynamic> json) {
    return MarketingContextMarket(
      id: _asInt(json['id']),
      name: json['name']?.toString() ?? '',
      district: json['district']?.toString(),
      companyName: json['companyName']?.toString(),
      sectorName: json['sectorName']?.toString(),
    );
  }
}

/// A dealer from the Sales master, offered by the existing-dealer picker.
///
/// [sourceId] is a **Sales** id. It is not an `mkt_parties` id and must never
/// be written as one — it exists so the autofill can record which ERP dealer a
/// record came from.
class MarketingDealer {
  const MarketingDealer({
    required this.sourceId,
    required this.name,
    this.code,
    this.contactPerson,
    this.phone,
    this.altPhone,
    this.address,
    this.zoneName,
    this.dealerGroup,
  });

  final int sourceId;
  final String name;
  final String? code;
  final String? contactPerson;
  final String? phone;
  final String? altPhone;
  final String? address;
  final String? zoneName;
  final String? dealerGroup;

  String get displayName => name.trim().isEmpty ? 'Dealer #$sourceId' : name;

  String get subtitle => [
        code,
        contactPerson,
        phone,
      ].where((part) => part != null && part.trim().isNotEmpty).join(' · ');

  String get searchText => [
        name,
        code ?? '',
        contactPerson ?? '',
        phone ?? '',
        zoneName ?? '',
      ].join(' ').toLowerCase();

  factory MarketingDealer.fromJson(Map<String, dynamic> json) {
    return MarketingDealer(
      sourceId: _asInt(json['sourceId']),
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString(),
      contactPerson: json['contactPerson']?.toString(),
      phone: json['phone']?.toString(),
      altPhone: json['altPhone']?.toString(),
      address: json['address']?.toString(),
      zoneName: json['zoneName']?.toString(),
      dealerGroup: json['dealerGroup']?.toString(),
    );
  }

  /// Adapts the older `AllDealerLists` shape (fetched straight from Sales) onto
  /// this model, so callers do not have to care which source answered.
  factory MarketingDealer.fromSalesItem(DealerListItem item) {
    return MarketingDealer(
      sourceId: item.id,
      name: item.tradeName,
      code: item.dealerCode,
      contactPerson: item.contactPerson,
      phone: item.phone,
      zoneName: item.zoneName,
    );
  }
}

Map<String, dynamic>? _object(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

List<Map<String, dynamic>> _list(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _asIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}