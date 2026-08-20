import '../models/booking_form_data_models.dart';

/// Opaque ERP-style IDs for Farm & Dealer forms until live master APIs exist.
class MarketingDemoNamed {
  const MarketingDemoNamed({
    required this.id,
    required this.name,
    this.subtitle,
  });

  final int id;
  final String name;
  final String? subtitle;

  String get displayName => name;

  String get searchText =>
      '$name ${subtitle ?? ''} $id'.toLowerCase();

  @override
  bool operator ==(Object other) =>
      other is MarketingDemoNamed && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class MarketingDemoProduct {
  const MarketingDemoProduct({
    required this.id,
    required this.name,
    this.categoryId,
    this.companyId,
    this.categoryName,
    this.ourProduct = true,
  });

  final int id;
  final String name;
  final int? categoryId;
  final int? companyId;
  final String? categoryName;
  final bool ourProduct;

  String get displayName => name;

  String get searchText =>
      '$name ${categoryName ?? ''} $id'.toLowerCase();

  @override
  bool operator ==(Object other) =>
      other is MarketingDemoProduct && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class MarketingDemoMasters {
  MarketingDemoMasters._();

  static const companies = <BookingFormCompany>[
    BookingFormCompany(id: 1, nameEn: 'Peoples Poultry & Hatchery Ltd'),
    BookingFormCompany(id: 2, nameEn: 'Peoples Feed'),
  ];

  static const sectors = <BookingFormSector>[
    BookingFormSector(id: 11, name: 'Live Bird (Dhaka)', companyId: 1),
    BookingFormSector(id: 12, name: 'Feed (Munshiganj)', companyId: 2),
    BookingFormSector(id: 13, name: 'Chicks (Sreenagar)', companyId: 1),
  ];

  static const dealers = <MarketingDemoNamed>[
    MarketingDemoNamed(
      id: 501,
      name: 'Bismillah PPHL Feed',
      subtitle: 'Existing ERP dealer',
    ),
    MarketingDemoNamed(
      id: 502,
      name: 'Sunrise Agro Store',
      subtitle: 'Existing ERP dealer',
    ),
    MarketingDemoNamed(
      id: 503,
      name: 'City Farm Depot',
      subtitle: 'Existing ERP dealer',
    ),
  ];

  static const categories = <MarketingDemoNamed>[
    MarketingDemoNamed(id: 21, name: 'Feed'),
    MarketingDemoNamed(id: 22, name: 'Chicks'),
    MarketingDemoNamed(id: 23, name: 'Medicine'),
    MarketingDemoNamed(id: 24, name: 'Fertilizer'),
  ];

  static const units = <MarketingDemoNamed>[
    MarketingDemoNamed(id: 31, name: 'KG'),
    MarketingDemoNamed(id: 32, name: 'Bag'),
    MarketingDemoNamed(id: 33, name: 'Pcs'),
    MarketingDemoNamed(id: 34, name: 'Acre'),
    MarketingDemoNamed(id: 35, name: 'Decimal'),
  ];

  static const employees = <MarketingDemoNamed>[
    MarketingDemoNamed(
      id: 1001,
      name: 'Sales officer 1001',
      subtitle: 'Technical service',
    ),
    MarketingDemoNamed(
      id: 1002,
      name: 'Sales officer 1002',
      subtitle: 'Collection',
    ),
    MarketingDemoNamed(
      id: 1003,
      name: 'Sales officer 1003',
      subtitle: 'Dealer development',
    ),
  ];

  static const products = <MarketingDemoProduct>[
    MarketingDemoProduct(
      id: 101,
      name: 'Peoples Feed Grower',
      categoryId: 21,
      companyId: 2,
      categoryName: 'Feed',
    ),
    MarketingDemoProduct(
      id: 102,
      name: 'Peoples Feed Layer',
      categoryId: 21,
      companyId: 2,
      categoryName: 'Feed',
    ),
    MarketingDemoProduct(
      id: 103,
      name: 'Peoples DOC Chicks',
      categoryId: 22,
      companyId: 1,
      categoryName: 'Chicks',
    ),
    MarketingDemoProduct(
      id: 104,
      name: 'Competitor Feed',
      categoryId: 21,
      companyId: 2,
      categoryName: 'Feed',
      ourProduct: false,
    ),
  ];

  static List<BookingFormCompany> companiesOr(List<BookingFormCompany> live) {
    final usable = live.where((c) => c.id > 0).toList();
    return usable.isNotEmpty ? usable : companies;
  }

  static List<BookingFormSector> sectorsOr(List<BookingFormSector> live) {
    final usable = live.where((s) => s.id > 0).toList();
    return usable.isNotEmpty ? usable : sectors;
  }

  static T? byId<T>(List<T> items, int? id, int Function(T item) getId) {
    if (id == null) return null;
    for (final item in items) {
      if (getId(item) == id) return item;
    }
    return null;
  }
}

String marketingNewClientUuid() {
  final millis = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  final padded = millis.padLeft(16, '0');
  return 'mkt-$padded';
}
