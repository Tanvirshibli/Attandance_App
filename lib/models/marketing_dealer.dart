import 'dealer_list_models.dart';

/// A dealer from the Sales master, offered by the existing-dealer picker.
///
/// [sourceId] is a **Sales** id. It is not an `mkt_parties` id and must never
/// be written as one — it exists so the autofill can record which ERP dealer a
/// record came from.
///
/// The Sales dealer master carries no company or sector edge (a row is
/// `tradeName`, `dealerCode`, `contactPerson`, `phone` and a zone), so this
/// picker cannot be narrowed by the company the officer picked and is offered
/// unfiltered instead.
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

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
