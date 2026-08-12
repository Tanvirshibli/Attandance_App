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

  factory BookingFormSector.fromJson(Map<String, dynamic> json) {
    return BookingFormSector(
      id: _asInt(json['id']) ?? 0,
      name: json['name']?.toString() ?? 'Sector ${json['id']}',
      companyId: _asInt(json['companyId'] ?? json['company_id']),
    );
  }
}

class BookingFormData {
  const BookingFormData({
    required this.companies,
    required this.sectors,
  });

  final List<BookingFormCompany> companies;
  final List<BookingFormSector> sectors;

  List<BookingFormSector> sectorsForCompany(int? companyId) {
    if (companyId == null) return const [];
    return sectors.where((s) => s.companyId == companyId).toList();
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

    for (final moduleKey in ['feed', 'chicks']) {
      final module = data[moduleKey];
      if (module is! Map) continue;
      final map = Map<String, dynamic>.from(module);
      ingestCompanies(map['companyList']);
      ingestSectors(map['sectorList']);
    }

    // Also accept top-level lists if API shape changes.
    ingestCompanies(data['companyList']);
    ingestSectors(data['sectorList']);

    final companies = companiesById.values.toList()
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    final sectors = sectorsById.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return BookingFormData(companies: companies, sectors: sectors);
  }
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}
