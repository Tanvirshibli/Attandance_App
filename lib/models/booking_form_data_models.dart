/// Masters from Sales `GET /api/booking-person-books/form-data`.
class BookingFormCompany {
  const BookingFormCompany({
    required this.id,
    required this.nameEn,
    this.nameBn,
  });

  final int id;
  final String nameEn;
  final String? nameBn;

  String get displayName =>
      nameEn.trim().isNotEmpty ? nameEn.trim() : (nameBn?.trim() ?? 'Company $id');

  factory BookingFormCompany.fromJson(Map<String, dynamic> json) {
    return BookingFormCompany(
      id: _asInt(json['id']) ?? 0,
      nameEn: json['nameEn']?.toString() ?? json['name']?.toString() ?? '',
      nameBn: json['nameBn']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BookingFormCompany && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class BookingFormSector {
  const BookingFormSector({
    required this.id,
    required this.name,
    this.companyId,
  });

  final int id;
  final String name;
  final int? companyId;

  String get searchText => name.toLowerCase();

  factory BookingFormSector.fromJson(Map<String, dynamic> json) {
    return BookingFormSector(
      id: _asInt(json['id']) ?? 0,
      name: json['name']?.toString() ??
          json['salesPointName']?.toString() ??
          'Sector ${json['id']}',
      companyId: _asInt(json['companyId'] ?? json['company_id']),
    );
  }

  @override
  bool operator ==(Object other) => other is BookingFormSector && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class BookingFormCategory {
  const BookingFormCategory({required this.id, required this.name});

  final int id;
  final String name;

  String get searchText => name.toLowerCase();

  factory BookingFormCategory.fromJson(Map<String, dynamic> json) {
    return BookingFormCategory(
      id: _asInt(json['id']) ?? 0,
      name: json['name']?.toString() ?? 'Category ${json['id']}',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BookingFormCategory && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class BookingFormSubCategory {
  const BookingFormSubCategory({required this.id, required this.name});

  final int id;
  final String name;

  String get searchText => name.toLowerCase();

  factory BookingFormSubCategory.fromJson(Map<String, dynamic> json) {
    return BookingFormSubCategory(
      id: _asInt(json['id']) ?? 0,
      name: json['subCategoryName']?.toString() ??
          json['name']?.toString() ??
          'Sub ${json['id']}',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BookingFormSubCategory && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class BookingFormChildCategory {
  const BookingFormChildCategory({
    required this.id,
    required this.name,
    this.subCategoryId,
  });

  final int id;
  final String name;
  final int? subCategoryId;

  String get searchText => name.toLowerCase();

  factory BookingFormChildCategory.fromJson(Map<String, dynamic> json) {
    return BookingFormChildCategory(
      id: _asInt(json['id']) ?? 0,
      name: json['childCategoryName']?.toString() ??
          json['name']?.toString() ??
          'Child ${json['id']}',
      subCategoryId: _asInt(json['subCategoryId'] ?? json['sub_category_id']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BookingFormChildCategory && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class BookingFormProductPrice {
  const BookingFormProductPrice({
    required this.productId,
    required this.productName,
    required this.tradePrice,
    this.shortName,
    this.categoryId,
    this.subCategoryId,
    this.childCategoryId,
    this.priceId,
  });

  final int productId;
  final String productName;
  final double tradePrice;
  final String? shortName;
  final int? categoryId;
  final int? subCategoryId;
  final int? childCategoryId;
  final int? priceId;

  String get displayLabel {
    final short = shortName?.trim();
    if (short != null && short.isNotEmpty) return '$productName ($short)';
    return productName;
  }

  String get searchText =>
      '${productName.toLowerCase()} ${shortName?.toLowerCase() ?? ''} $productId';

  factory BookingFormProductPrice.fromJson(Map<String, dynamic> json) {
    return BookingFormProductPrice(
      productId: _asInt(json['productId'] ?? json['product_id']) ?? 0,
      productName: json['productName']?.toString() ??
          json['product_name']?.toString() ??
          'Product',
      tradePrice: _asDouble(json['tradePrice'] ?? json['trade_price']) ?? 0,
      shortName: json['shortName']?.toString() ?? json['short_name']?.toString(),
      categoryId: _asInt(json['categoryId'] ?? json['category_id']),
      subCategoryId: _asInt(json['subCategoryId'] ?? json['sub_category_id']),
      childCategoryId: _asInt(json['childCategoryId'] ?? json['child_category_id']),
      priceId: _asInt(json['priceId'] ?? json['price_id']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BookingFormProductPrice && other.productId == productId;

  @override
  int get hashCode => productId.hashCode;
}

class BookingFormChicksProduct {
  const BookingFormChicksProduct({
    required this.sectorId,
    required this.productId,
    required this.productName,
    this.shortName,
    this.closingBalance,
  });

  final int sectorId;
  final int productId;
  final String productName;
  final String? shortName;
  final double? closingBalance;

  String get displayLabel {
    final short = shortName?.trim();
    final name = (short != null && short.isNotEmpty)
        ? '$productName ($short)'
        : productName;
    if (closingBalance != null) {
      return '$name · ${closingBalance!.round()}';
    }
    return name;
  }

  String get searchText =>
      '${productName.toLowerCase()} ${shortName?.toLowerCase() ?? ''} $productId';

  factory BookingFormChicksProduct.fromJson(Map<String, dynamic> json) {
    return BookingFormChicksProduct(
      sectorId: _asInt(json['sectorId'] ?? json['sector_id']) ?? 0,
      productId: _asInt(json['productId'] ?? json['product_id']) ?? 0,
      productName: json['productName']?.toString() ??
          json['productname']?.toString() ??
          'Product',
      shortName: json['shortName']?.toString() ?? json['shortname']?.toString(),
      closingBalance: _asDouble(
        json['closingBalance'] ?? json['closing_balance'],
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BookingFormChicksProduct &&
      other.productId == productId &&
      other.sectorId == sectorId;

  @override
  int get hashCode => Object.hash(productId, sectorId);
}

class BookingFormZone {
  const BookingFormZone({required this.id, required this.name});

  final int id;
  final String name;

  String get searchText => name.toLowerCase();

  factory BookingFormZone.fromJson(Map<String, dynamic> json) {
    return BookingFormZone(
      id: _asInt(json['id']) ?? 0,
      name: json['zoneName']?.toString() ??
          json['name']?.toString() ??
          'Zone ${json['id']}',
    );
  }

  @override
  bool operator ==(Object other) => other is BookingFormZone && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class BookingFormData {
  const BookingFormData({
    required this.companies,
    required this.sectors,
    this.feedCategories = const [],
    this.feedSubCategories = const [],
    this.feedChildCategories = const [],
    this.feedSalesPoints = const [],
    this.feedProductPrices = const [],
    this.chicksCategories = const [],
    this.chicksSectors = const [],
    this.chicksProducts = const [],
    this.chicksZones = const [],
  });

  final List<BookingFormCompany> companies;
  final List<BookingFormSector> sectors;
  final List<BookingFormCategory> feedCategories;
  final List<BookingFormSubCategory> feedSubCategories;
  final List<BookingFormChildCategory> feedChildCategories;
  final List<BookingFormSector> feedSalesPoints;
  final List<BookingFormProductPrice> feedProductPrices;
  final List<BookingFormCategory> chicksCategories;
  final List<BookingFormSector> chicksSectors;
  final List<BookingFormChicksProduct> chicksProducts;
  final List<BookingFormZone> chicksZones;

  List<BookingFormSector> sectorsForCompany(int? companyId) {
    if (companyId == null) return const [];
    return sectors.where((s) => s.companyId == companyId).toList();
  }

  List<BookingFormSubCategory> feedSubsForCategory(int? categoryId) {
    if (categoryId == null) return feedSubCategories;
    final ids = feedProductPrices
        .where((p) => p.categoryId == categoryId)
        .map((p) => p.subCategoryId)
        .whereType<int>()
        .toSet();
    if (ids.isEmpty) return feedSubCategories;
    return feedSubCategories.where((s) => ids.contains(s.id)).toList();
  }

  List<BookingFormChildCategory> feedChildrenForSub(int? subCategoryId) {
    if (subCategoryId == null) return feedChildCategories;
    return feedChildCategories
        .where((c) => c.subCategoryId == subCategoryId)
        .toList();
  }

  List<BookingFormProductPrice> feedProductsFor({
    int? categoryId,
    int? subCategoryId,
    int? childCategoryId,
  }) {
    return feedProductPrices.where((p) {
      if (categoryId != null && p.categoryId != categoryId) return false;
      if (subCategoryId != null && p.subCategoryId != subCategoryId) {
        return false;
      }
      if (childCategoryId != null && p.childCategoryId != childCategoryId) {
        return false;
      }
      return p.productId > 0;
    }).toList();
  }

  List<BookingFormChicksProduct> chicksProductsForSector(int? sectorId) {
    if (sectorId == null) return const [];
    return chicksProducts.where((p) => p.sectorId == sectorId).toList();
  }

  /// Mobile POST still requires category/sub/child for chicks.
  ({int categoryId, int subCategoryId, int childCategoryId})?
      resolveChicksCategoryIds() {
    final cats =
        chicksCategories.isNotEmpty ? chicksCategories : feedCategories;
    BookingFormCategory? category;
    for (final item in cats) {
      if (item.name.toLowerCase().contains('chick')) {
        category = item;
        break;
      }
    }
    category ??= cats.isNotEmpty ? cats.first : null;
    if (category == null) return null;

    BookingFormChildCategory? child;
    if (feedChildCategories.isNotEmpty) {
      child = feedChildCategories.first;
    }
    if (child != null) {
      final subId = child.subCategoryId ??
          (feedSubCategories.isNotEmpty ? feedSubCategories.first.id : null);
      if (subId != null) {
        return (
          categoryId: category.id,
          subCategoryId: subId,
          childCategoryId: child.id,
        );
      }
    }
    if (feedSubCategories.isNotEmpty) {
      return (
        categoryId: category.id,
        subCategoryId: feedSubCategories.first.id,
        childCategoryId: feedChildCategories.isNotEmpty
            ? feedChildCategories.first.id
            : feedSubCategories.first.id,
      );
    }
    return null;
  }

  factory BookingFormData.fromApiData(Map<String, dynamic> data) {
    final companiesById = <int, BookingFormCompany>{};
    final sectorsById = <int, BookingFormSector>{};

    void ingestCompanies(dynamic raw) {
      if (raw is! List) return;
      for (final item in raw) {
        if (item is! Map) continue;
        final c = BookingFormCompany.fromJson(Map<String, dynamic>.from(item));
        if (c.id > 0) companiesById[c.id] = c;
      }
    }

    void ingestSectors(dynamic raw) {
      if (raw is! List) return;
      for (final item in raw) {
        if (item is! Map) continue;
        final s = BookingFormSector.fromJson(Map<String, dynamic>.from(item));
        if (s.id > 0) sectorsById[s.id] = s;
      }
    }

    List<T> parseList<T>(dynamic raw, T Function(Map<String, dynamic>) map) {
      if (raw is! List) return <T>[];
      return raw
          .whereType<Map>()
          .map((e) => map(Map<String, dynamic>.from(e)))
          .toList();
    }

    Map<String, dynamic> moduleMap(String key) {
      final module = data[key];
      if (module is Map) return Map<String, dynamic>.from(module);
      return const {};
    }

    final feed = moduleMap('feed');
    final chicks = moduleMap('chicks');

    ingestCompanies(feed['companyList']);
    ingestCompanies(chicks['companyList']);
    ingestCompanies(data['companyList']);
    ingestSectors(chicks['sectorList']);
    ingestSectors(data['sectorList']);

    final companies = companiesById.values.toList()
      ..sort(
        (a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
      );
    final sectors = sectorsById.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final feedSalesPoints = parseList(feed['salesPointList'], BookingFormSector.fromJson)
        .where((s) => s.id > 0)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final chicksSectors = parseList(chicks['sectorList'], BookingFormSector.fromJson)
        .where((s) => s.id > 0)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final chicksZones = <BookingFormZone>[
      ...parseList(chicks['zoneList'], BookingFormZone.fromJson),
      ...parseList(chicks['cZoneList'], BookingFormZone.fromJson),
      ...parseList(chicks['chicksZoneList'], BookingFormZone.fromJson),
    ].where((z) => z.id > 0).toList();

    return BookingFormData(
      companies: companies,
      sectors: sectors,
      feedCategories: parseList(feed['categoryList'], BookingFormCategory.fromJson)
          .where((c) => c.id > 0)
          .toList(),
      feedSubCategories:
          parseList(feed['subCategoryList'], BookingFormSubCategory.fromJson)
              .where((c) => c.id > 0)
              .toList(),
      feedChildCategories:
          parseList(feed['childCategoryList'], BookingFormChildCategory.fromJson)
              .where((c) => c.id > 0)
              .toList(),
      feedSalesPoints: feedSalesPoints,
      feedProductPrices:
          parseList(feed['productDailyPriceList'], BookingFormProductPrice.fromJson)
              .where((p) => p.productId > 0)
              .toList(),
      chicksCategories:
          parseList(chicks['categoryList'], BookingFormCategory.fromJson)
              .where((c) => c.id > 0)
              .toList(),
      chicksSectors: chicksSectors,
      chicksProducts:
          parseList(chicks['productList'], BookingFormChicksProduct.fromJson)
              .where((p) => p.productId > 0)
              .toList(),
      chicksZones: chicksZones,
    );
  }
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}
