/// Wire models for the Sales zone master (`GET /api/get-zone`).
///
/// The endpoint is public (no auth) and returns:
/// `{ "message": "Success!", "data": [ { id, zoneName, zonalInCharge,
///   districts: [{ id, name }], note } ] }`
///
/// Zone ids here are the **sales** zone ids. HRM stores the employee's zones
/// in the same numbering, but that is a coincidence of convention — across
/// systems zones are joined by name, never by id.
class ZoneDistrict {
  const ZoneDistrict({required this.id, required this.name});

  final int id;
  final String name;

  factory ZoneDistrict.fromJson(Map<String, dynamic> json) {
    return ZoneDistrict(
      id: _zoneToInt(json['id']) ?? 0,
      name: _zoneNonEmpty([
        json['name'],
        json['districtName'],
        json['district_name'],
      ]),
    );
  }

  @override
  bool operator ==(Object other) => other is ZoneDistrict && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class SalesZone {
  const SalesZone({
    required this.id,
    required this.zoneName,
    this.zonalInCharge,
    this.districts = const [],
    this.note,
  });

  final int id;
  final String zoneName;
  final String? zonalInCharge;
  final List<ZoneDistrict> districts;
  final String? note;

  factory SalesZone.fromJson(Map<String, dynamic> json) {
    return SalesZone(
      id: _zoneToInt(json['id']) ?? 0,
      zoneName: _zoneNonEmpty([
        json['zoneName'],
        json['zone_name'],
        json['name'],
      ]),
      zonalInCharge: _zoneNullableText(json['zonalInCharge'] ?? json['zonal_in_charge']),
      districts: _zoneDistricts(json['districts']),
      note: _zoneNullableText(json['note']),
    );
  }

  /// Parses the `get-zone` envelope. Tolerates the `records` / `items` keys the
  /// other Sales list endpoints use, and drops rows that carry no usable id or
  /// name so a malformed entry cannot widen the scope.
  static List<SalesZone> listFrom(Map<String, dynamic> json) {
    Object? raw = json['data'];
    if (raw is! List) {
      raw = json['records'] ?? json['items'];
    }
    if (raw is! List) return const [];

    final zones = <SalesZone>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final zone = SalesZone.fromJson(Map<String, dynamic>.from(item));
      if (zone.id > 0 && zone.zoneName.isNotEmpty) {
        zones.add(zone);
      }
    }
    return zones;
  }

  @override
  bool operator ==(Object other) => other is SalesZone && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

List<ZoneDistrict> _zoneDistricts(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((e) => ZoneDistrict.fromJson(Map<String, dynamic>.from(e)))
      .where((d) => d.id > 0 && d.name.isNotEmpty)
      .toList();
}

int? _zoneToInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString().trim() ?? '');
}

String _zoneNonEmpty(List<Object?> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty && text.toLowerCase() != 'null') {
      return text;
    }
  }
  return '';
}

String? _zoneNullableText(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text.toLowerCase() == 'null') return null;
  return text;
}
