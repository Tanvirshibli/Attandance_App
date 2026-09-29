import 'zone_models.dart';

/// The set of zones the logged-in employee is assigned to, resolved from the
/// HRM profile's `zoneId` list against the Sales zone master.
///
/// An employee can hold several zones, and the data they see is the **union**
/// of all of them — there is no "active zone" and no switcher.
///
/// A row belongs to the scope when any of these hold:
///  * its `zone_id` is one of the assigned zone ids;
///  * its `zone_name` matches an assigned zone name (case-insensitively);
///  * its district matches one of the assigned zones' districts.
///
/// The district test exists because the marketing tables predate zone tagging:
/// every market, party and visit created before the zone columns were added
/// carries `zone_id = NULL`, so an id-only test would hide all of them.
/// `mkt_markets.district` is free text rather than an id, hence the
/// bidirectional containment rather than equality.
///
/// Rows with no zone **and** no matching district are excluded — they belong to
/// no zone the employee is assigned to.
class ZoneScope {
  const ZoneScope({
    required this.zoneIds,
    required this.zoneNames,
    required this.districtNames,
    required this.displayNames,
  });

  /// Assigned zone ids, lowercased names, and the union of their districts.
  final Set<int> zoneIds;
  final Set<String> zoneNames;
  final Set<String> districtNames;

  /// Assigned zone names in their original casing, for display.
  final List<String> displayNames;

  /// Resolves [ids] against the Sales [zones] master.
  ///
  /// Ids the master does not know are skipped; when nothing resolves the scope
  /// is empty and [isEmpty] reports true so callers can fall back to
  /// unfiltered lists.
  factory ZoneScope.fromZones(List<int> ids, List<SalesZone> zones) {
    if (ids.isEmpty || zones.isEmpty) {
      return const ZoneScope(
        zoneIds: {},
        zoneNames: {},
        districtNames: {},
        displayNames: [],
      );
    }

    final wanted = ids.toSet();
    final zoneIds = <int>{};
    final zoneNames = <String>{};
    final districtNames = <String>{};
    final displayNames = <String>[];

    for (final zone in zones) {
      if (!wanted.contains(zone.id)) continue;

      zoneIds.add(zone.id);
      displayNames.add(zone.zoneName);
      final key = zone.zoneName.toLowerCase();
      zoneNames.add(key);
      for (final district in zone.districts) {
        districtNames.add(district.name.toLowerCase());
      }
    }

    return ZoneScope(
      zoneIds: zoneIds,
      zoneNames: zoneNames,
      districtNames: districtNames,
      displayNames: displayNames,
    );
  }

  bool get isEmpty => zoneIds.isEmpty || zoneNames.isEmpty;

  /// Human-readable zone list, e.g. `Zone A · Zone B`.
  String get label => displayNames.join(' · ');

  /// District names across every assigned zone, for diagnostics and empty
  /// states — e.g. `Gazipur, Jamalpur, Tangail`.
  String get districtSummary => districtNames.join(', ');

  /// Whether a marketing row belongs to this scope.
  bool matches({int? zoneId, String? zoneName, String? district}) {
    if (isEmpty) return true;

    if (zoneId != null && zoneId > 0 && zoneIds.contains(zoneId)) {
      return true;
    }

    final name = zoneName?.trim().toLowerCase() ?? '';
    if (name.isNotEmpty && zoneNames.contains(name)) {
      return true;
    }

    final place = district?.trim().toLowerCase() ?? '';
    if (place.isEmpty) return false;
    for (final known in districtNames) {
      if (place.contains(known) || known.contains(place)) {
        return true;
      }
    }

    return false;
  }

  Map<String, dynamic> toJson() {
    return {
      'zoneIds': zoneIds.toList()..sort(),
      'zoneNames': zoneNames.toList()..sort(),
      'districtNames': districtNames.toList()..sort(),
      'displayNames': displayNames,
    };
  }

  factory ZoneScope.fromJson(Map<String, dynamic> json) {
    List<String> names(Object? value) {
      if (value is! List) return const [];
      return value
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
    }

    final ids = <int>{};
    for (final value in json['zoneIds'] ?? const <dynamic>[]) {
      if (value is int) {
        ids.add(value);
      } else {
        final parsed = int.tryParse(value?.toString().trim() ?? '');
        if (parsed != null && parsed > 0) ids.add(parsed);
      }
    }

    return ZoneScope(
      zoneIds: ids,
      zoneNames: names(json['zoneNames']).map((n) => n.toLowerCase()).toSet(),
      districtNames:
          names(json['districtNames']).map((n) => n.toLowerCase()).toSet(),
      displayNames: names(json['displayNames']),
    );
  }
}
