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
        return feed;
      case 'egg':
        return egg;
      case 'fertilizer':
        return fertilizer;
      case 'liveBird':
      case 'chicks':
      case 'cullBird':
        return liveBird;
      default:
        return const [];
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
}

int _toInt(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
