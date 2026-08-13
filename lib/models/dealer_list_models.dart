class AllDealerLists {
  const AllDealerLists({
    required this.egg,
    required this.feed,
    required this.fertilizer,
    required this.liveBird,
    required this.wastage,
  });

  final List<DealerListItem> egg;
  final List<DealerListItem> feed;
  final List<DealerListItem> fertilizer;
  final List<DealerListItem> liveBird;
  final List<DealerListItem> wastage;

  factory AllDealerLists.fromJson(Map<String, dynamic> json) {
    return AllDealerLists(
      egg: _parse(json['eggDealList']),
      feed: _parse(json['feedDealList']),
      fertilizer: _parse(json['fertilizerDealList']),
      liveBird: _parse(json['liveBirdDealList']),
      wastage: _parse(json['wastageDealList']),
    );
  }

  List<DealerListItem> listForModule(String moduleKey) {
    switch (moduleKey) {
      case 'feed':
      case 'chicks':
        return feed;
      case 'egg':
        return egg;
      case 'fertilizer':
        return fertilizer;
      case 'liveBird':
      case 'cullBird':
        return liveBird;
      default:
        return const [];
    }
  }

  List<DealerListItem> get allUnique {
    final byId = <int, DealerListItem>{};
    for (final list in [egg, feed, fertilizer, liveBird, wastage]) {
      for (final dealer in list) {
        if (dealer.id > 0) byId[dealer.id] = dealer;
      }
    }
    return byId.values.toList();
  }

  /// Dealer bucket for Receive Payment "Payment For" (web create-page cascade).
  List<DealerListItem> listForPaymentFor({int? id, String? name}) {
    final lower = (name ?? '').toLowerCase();
    if (lower.contains('cull') && lower.contains('bird')) return liveBird;
    if (lower.contains('live') && lower.contains('bird')) return liveBird;
    if (lower.contains('wastage')) return wastage;
    if (lower.contains('fertilizer')) return fertilizer;
    if (lower.contains('egg')) return egg;
    if (lower.contains('chick') || lower.contains('feed')) return feed;

    switch (id) {
      case 1:
      case 2:
        return feed;
      case 3:
      case 4:
        return liveBird;
      case 5:
        return egg;
      case 7:
        return fertilizer;
      case 11:
        return wastage;
      default:
        return allUnique;
    }
  }

  static List<DealerListItem> _parse(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => DealerListItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}

class DealerListItem {
  const DealerListItem({
    required this.id,
    required this.tradeName,
    this.dealerCode,
    this.contactPerson,
    this.phone,
    this.zoneName,
  });

  final int id;
  final String tradeName;
  final String? dealerCode;
  final String? contactPerson;
  final String? phone;
  final String? zoneName;

  String get subtitle {
    final parts = <String>[
      if (dealerCode != null && dealerCode!.isNotEmpty) dealerCode!,
      if (zoneName != null && zoneName!.isNotEmpty) zoneName!,
      if (phone != null && phone!.isNotEmpty) phone!,
    ];
    return parts.join(' · ');
  }

  String get searchText =>
      '${tradeName.toLowerCase()} ${dealerCode?.toLowerCase() ?? ''} '
      '${contactPerson?.toLowerCase() ?? ''} ${phone ?? ''} '
      '${zoneName?.toLowerCase() ?? ''}';

  factory DealerListItem.fromJson(Map<String, dynamic> json) {
    return DealerListItem(
      id: _toInt(json['id']),
      tradeName: json['tradeName']?.toString() ?? 'Dealer',
      dealerCode: json['dealerCode']?.toString(),
      contactPerson: json['contactPerson']?.toString(),
      phone: json['phone']?.toString(),
      zoneName: json['zoneName']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) => other is DealerListItem && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

int _toInt(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
