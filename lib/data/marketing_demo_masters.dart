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

  static const breeds = <MarketingDemoNamed>[
    MarketingDemoNamed(id: 201, name: 'CB'),
    MarketingDemoNamed(id: 202, name: 'Cobb 500'),
    MarketingDemoNamed(id: 203, name: 'Ross 308'),
    MarketingDemoNamed(id: 204, name: 'Hubbard'),
    MarketingDemoNamed(id: 205, name: 'Sonali'),
    MarketingDemoNamed(id: 206, name: 'Local'),
  ];

  static const docCompanies = <MarketingDemoNamed>[
    MarketingDemoNamed(id: 301, name: 'Provita'),
    MarketingDemoNamed(id: 302, name: 'Peoples Hatchery'),
    MarketingDemoNamed(id: 303, name: 'Aftab Hatchery'),
    MarketingDemoNamed(id: 304, name: 'Kazi Hatchery'),
    MarketingDemoNamed(id: 305, name: 'Demo Hatchery'),
  ];

  static const feedCompanies = <MarketingDemoNamed>[
    MarketingDemoNamed(id: 401, name: 'PPHL'),
    MarketingDemoNamed(id: 402, name: 'Peoples Feed'),
    MarketingDemoNamed(id: 403, name: 'Nourish Feed'),
    MarketingDemoNamed(id: 404, name: 'Quality Feed'),
    MarketingDemoNamed(id: 405, name: 'Competitor Feed'),
  ];

  static const shedDesigns = <MarketingDemoNamed>[
    MarketingDemoNamed(id: 501, name: 'Open shed'),
    MarketingDemoNamed(id: 502, name: 'Open'),
    MarketingDemoNamed(id: 503, name: 'Semi-closed'),
    MarketingDemoNamed(id: 504, name: 'Closed'),
  ];

  static const curtains = <MarketingDemoNamed>[
    MarketingDemoNamed(id: 511, name: 'Cloth'),
    MarketingDemoNamed(id: 512, name: 'Present'),
    MarketingDemoNamed(id: 513, name: 'Partial'),
    MarketingDemoNamed(id: 514, name: 'None'),
  ];

  static const floors = <MarketingDemoNamed>[
    MarketingDemoNamed(id: 521, name: 'Concrete house'),
    MarketingDemoNamed(id: 522, name: 'Litter'),
    MarketingDemoNamed(id: 523, name: 'Slatted'),
    MarketingDemoNamed(id: 524, name: 'Mixed'),
  ];

  static const territories = <MarketingDemoNamed>[
    MarketingDemoNamed(id: 601, name: 'Munshiganj East'),
    MarketingDemoNamed(id: 602, name: 'Sreenagar'),
    MarketingDemoNamed(id: 603, name: 'Savar'),
    MarketingDemoNamed(id: 604, name: 'Narayanganj'),
  ];

  static const zones = <MarketingDemoNamed>[
    MarketingDemoNamed(id: 701, name: 'A'),
    MarketingDemoNamed(id: 702, name: 'B'),
    MarketingDemoNamed(id: 703, name: 'C'),
    MarketingDemoNamed(id: 704, name: 'Dhaka South'),
    MarketingDemoNamed(id: 705, name: 'Dhaka North'),
    MarketingDemoNamed(id: 706, name: 'Chattogram'),
    MarketingDemoNamed(id: 707, name: 'Khulna'),
  ];

  static const visitTypes = <String>[
    'Regular farm visit',
    'Survey',
    'Technical support',
    'Other',
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
