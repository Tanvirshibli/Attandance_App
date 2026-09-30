import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../data/marketing_demo_masters.dart';
import '../models/marketing_context.dart';
import '../models/marketing_models.dart';
import 'auth_service.dart';
import 'marketing_service.dart';
import 'sales_service.dart';
import 'zone_scope_service.dart';

/// What the marketing forms derive from the logged-in employee.
///
/// Every member is nullable and independently resolved. A form shows what it
/// could resolve and omits the rest from the payload rather than guessing an
/// id — a wrong `company_id` silently files a dealer under another company,
/// which is worse than an empty column an admin can correct.
class EmployeeMarketingScope {
  const EmployeeMarketingScope({
    this.zone,
    this.company,
    this.sector,
    this.market,
  });

  const EmployeeMarketingScope.empty() : this();

  final MarketingDemoNamed? zone;
  final BookingFormCompany? company;
  final BookingFormSector? sector;
  final Market? market;

  bool get hasZone => zone != null;

  /// True when all four resolved — used only for diagnostics, never to block a
  /// form on a partial scope.
  bool get isComplete => hasZone && company != null && sector != null && market != null;

  Map<String, dynamic> toJson() => {
        'zone_id': zone?.id,
        'zone_name': zone?.name,
        'company_id': company?.id,
        'company_name': company?.displayName,
        'sector_id': sector?.id,
        'sector_name': sector?.name,
        'market_id': market?.id,
        'market_name': market?.displayName,
      };

  factory EmployeeMarketingScope.fromJson(Map<String, dynamic> json) {
    // Stored by id and name together so the restored scope can be shown without
    // another round-trip, but ids still come from the master, never from cache.
    return EmployeeMarketingScope(
      zone: _zoneFrom(json['zone_id'], json['zone_name']),
      company: json['company_id'] is int && json['company_name'] is String
          ? BookingFormCompany(
              id: json['company_id'] as int,
              nameEn: json['company_name'] as String,
            )
          : null,
      sector: json['sector_id'] is int && json['sector_name'] is String
          ? BookingFormSector(
              id: json['sector_id'] as int,
              name: json['sector_name'] as String,
            )
          : null,
    );
  }

  static MarketingDemoNamed? _zoneFrom(Object? id, Object? name) {
    if (id is! int || id <= 0) return null;
    final text = (name ?? '').toString().trim();
    if (text.isEmpty) return null;
    return MarketingDemoNamed(id: id, name: text);
  }
}

/// Resolves the zone, company, sector and market the logged-in employee works
/// in, so the dealer, farm and market forms can show them read-only instead of
/// asking a field officer to pick their own territory.
///
/// The three sources disagree on ids — HRM, Sales and ZKTeco each assign zone,
/// company and sector ids independently — so every join here is by **name**.
/// Ids are only ever read off a master that the id also came from.
class EmployeeMarketingScopeService {
  EmployeeMarketingScopeService._();
  static final EmployeeMarketingScopeService instance =
      EmployeeMarketingScopeService._();

  static const String _cacheKey = 'employee_marketing_scope_json';
  static const String _cacheAtKey = 'employee_marketing_scope_resolved_at_ms';
  static const Duration _cacheTtl = Duration(hours: 24);

  final AuthService _authService = AuthService();
  final SalesService _salesService = SalesService();
  final MarketingService _marketingService = MarketingService();

  EmployeeMarketingScope? _cached;
  bool _resolving = false;

  EmployeeMarketingScope? get cached => _cached;

  /// The employee's scope. Never throws and never returns null — an
  /// unresolvable scope comes back as [EmployeeMarketingScope.empty] so callers
  /// do not have to handle a missing service result.
  ///
  /// [lat] / [lng] come from the form's own GPS capture and decide which market
  /// inside the zone is closest; passing null falls back to the newest one.
  Future<EmployeeMarketingScope> load({
    double? lat,
    double? lng,
    bool forceRefresh = false,
  }) async {
    final profile = _authService.cachedProfileOrNull ??
        await _authService.getCurrentUserProfile();
    if (profile == null) return const EmployeeMarketingScope.empty();

    if (!forceRefresh && lat == null && lng == null) {
      final cached = await _fromCache();
      if (cached != null) return cached;
    }

    if (_resolving) {
      return _cached ?? const EmployeeMarketingScope.empty();
    }
    _resolving = true;

    try {
      final scope = await _resolve(profile.sector, lat, lng);
      // Only the market-less part is worth caching: it depends on masters that
      // change slowly, while the market depends on where the officer is
      // standing right now.
      if (scope.zone != null || scope.company != null || scope.sector != null) {
        _cached = scope;
        await _persist(scope);
      }
      return scope;
    } catch (_) {
      return _cached ?? const EmployeeMarketingScope.empty();
    } finally {
      _resolving = false;
    }
  }

  Future<EmployeeMarketingScope> _resolve(
    String profileSector,
    double? lat,
    double? lng,
  ) async {
    final zone = await _resolveZone();

    // The real relation, resolved by the backend from the synced marketing org
    // master. This replaces guessing a company by name-matching HRM's single
    // free-text `sector` against two unrelated Sales lists — a guess that could
    // only fail, because HRM exposes no company at all and the sector name is
    // frequently the literal string 'N/A'.
    final contextResult = await _marketingService.loadMarketingContext(
      zoneName: zone?.name,
      lat: lat,
      lng: lng,
    );
    final context = contextResult.success
        ? (contextResult.data ?? const MarketingContext.empty())
        : const MarketingContext.empty();

    if (context.zone != null || context.company != null) {
      return EmployeeMarketingScope(
        zone: zone ?? _zoneFromContext(context),
        company: _companyFromContext(context),
        sector: _sectorFromContext(context),
        market: context.markets.isNotEmpty
            ? Market.fromJson(_marketJson(context.markets.first))
            : await _resolveMarket(zone, await ZoneScopeService.instance.loadZoneDistricts(), lat, lng),
      );
    }

    // The master has nothing for this zone yet. Fall back to the old name
    // match so a partially configured deployment still shows what it can, and
    // an unreachable backend degrades to the zone alone rather than breaking
    // the form.
    final districts = await ZoneScopeService.instance.loadZoneDistricts();
    final formData = await _salesService.fetchBookingFormData();

    final companies = MarketingDemoMasters.companiesOr(
      formData.success ? (formData.data?.companies ?? const []) : const [],
    );
    final sectors = MarketingDemoMasters.sectorsOr(
      formData.success ? (formData.data?.sectors ?? const []) : const [],
    );

    final needle = _normalise(profileSector);

    return EmployeeMarketingScope(
      zone: zone,
      company: _match(companies, needle, (c) => c.displayName, (c) => c.id),
      sector: _match(sectors, needle, (s) => s.name, (s) => s.id),
      market: await _resolveMarket(zone, districts, lat, lng),
    );
  }

  /// The backend zone expressed as the local option shape the scope holds.
  static MarketingDemoNamed? _zoneFromContext(MarketingContext context) {
    final zone = context.zone;
    if (zone == null || zone.id <= 0 || zone.name.trim().isEmpty) return null;
    return MarketingDemoNamed(id: zone.id, name: zone.name);
  }

  static BookingFormCompany? _companyFromContext(MarketingContext context) {
    final company = context.company;
    if (company == null || company.id <= 0) return null;
    return BookingFormCompany(id: company.id, nameEn: company.name);
  }

  static BookingFormSector? _sectorFromContext(MarketingContext context) {
    final sector = context.sector;
    if (sector == null || sector.id <= 0) return null;
    return BookingFormSector(id: sector.id, name: sector.name);
  }

  /// The context market reshaped into the [Market] the forms already consume.
  ///
  /// Rebuilt field by field rather than fed through `Market.fromJson` so the
  /// context endpoint does not have to echo the whole market payload — it only
  /// promises the fields the scope actually needs.
  static Map<String, dynamic> _marketJson(MarketingContextMarket market) {
    return {
      'id': market.id,
      'name': market.name,
      if (market.district != null) 'district': market.district,
    };
  }

  Future<MarketingDemoNamed?> _resolveZone() async {
    final scope = await ZoneScopeService.instance.load();
    if (scope == null || scope.isEmpty) return null;

    // First assigned zone wins. scope.zoneNames is lowercase; the option list is
    // matched on the same normalised form so casing cannot hide a match.
    final options = await ZoneScopeService.instance.loadZoneOptions();
    for (final option in options) {
      if (scope.zoneNames.contains(_normalise(option.name))) {
        return option;
      }
    }
    return null;
  }

  /// The market nearest the captured position, among the markets in the zone.
  ///
  /// A zone normally holds several markets, so there is no single correct one to
  /// derive from the employee's profile — which is why this uses the form's own
  /// GPS rather than the first row, and why it stays read-only but visible: an
  /// officer who sees the wrong market can report it instead of the dealer being
  /// silently filed elsewhere.
  Future<Market?> _resolveMarket(
    MarketingDemoNamed? zone,
    Map<String, Set<String>> zoneDistricts,
    double? lat,
    double? lng,
  ) async {
    final result = await _marketingService.listMarkets();
    if (!result.success) return null;

    final markets = result.data ?? const <Market>[];
    if (markets.isEmpty) return null;

    final inZone = markets.where((m) => _marketInZone(m, zone, zoneDistricts)).toList();
    final candidates = inZone.isEmpty ? markets : inZone;

    candidates.sort((a, b) {
      final da = _distanceKm(lat, lng, a);
      final db = _distanceKm(lat, lng, b);
      if (da != db) return da.compareTo(db);
      // Ties and coordinate-less markets both fall back to the newest record.
      return b.id.compareTo(a.id);
    });
    return candidates.first;
  }

  /// Whether a market sits inside [zone].
  ///
  /// Mirrors the hub's predicate — a market tagged with the zone qualifies by
  /// zone id or zone name, and an untagged one is rescued through the districts
  /// of that zone. Ids are compared only against the ZKTeco market's own zone
  /// id, never against an HRM zone id; the district test uses bidirectional
  /// containment because `mkt_markets.district` is free text, not a foreign key.
  bool _marketInZone(
    Market market,
    MarketingDemoNamed? zone,
    Map<String, Set<String>> zoneDistricts,
  ) {
    if (zone == null) return true;

    if (market.zoneId != null && market.zoneId == zone.id) return true;
    if (_normalise(market.zoneName) == _normalise(zone.name)) return true;

    final districts = zoneDistricts[_normalise(zone.name)];
    if (districts == null || districts.isEmpty) return false;

    final place = _normalise(market.district);
    if (place.isEmpty) return false;
    for (final known in districts) {
      if (place.contains(known) || known.contains(place)) return true;
    }
    return false;
  }

  /// Great-circle distance in km, or infinity when either side has no position.
  ///
  /// A market without coordinates must not win on a zero distance, so it sorts
  /// last via infinity rather than being treated as nearest.
  static double _distanceKm(double? lat, double? lng, Market market) {
    final mLat = market.lat;
    final mLng = market.lng;
    if (lat == null || lng == null || mLat == null || mLng == null) {
      return double.infinity;
    }

    const earthRadiusKm = 6371.0;
    double toRad(double deg) => deg * math.pi / 180.0;

    final dLat = toRad(mLat - lat);
    final dLng = toRad(mLng - lng);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(toRad(lat)) *
            math.cos(toRad(mLat)) *
            math.pow(math.sin(dLng / 2), 2);
    // Clamp guards against a >1 from floating point, which would make the
    // inverse sine NaN.
    final clamped = math.min(1.0, a.toDouble());
    final c = 2 *
        math.atan2(math.sqrt(clamped), math.sqrt(1 - clamped));
    return earthRadiusKm * c;
  }

  static String _normalise(String? value) =>
      (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// First option whose name matches [needle] exactly, then as a prefix.
  ///
  /// Exact-then-prefix rather than a plain `contains`: "Peoples Feed" must not
  /// resolve to "Peoples Feed (Chicks)" while the real one is in the list.
  static T? _match<T>(
    List<T> options,
    String needle,
    String Function(T) nameOf,
    int Function(T) idOf,
  ) {
    if (needle.isEmpty || needle == 'n/a') return null;

    T? prefixHit;
    for (final option in options) {
      if (idOf(option) <= 0) continue;
      final name = _normalise(nameOf(option));
      if (name.isEmpty) continue;
      if (name == needle) return option;
      if (prefixHit == null && name.startsWith('$needle ')) {
        prefixHit = option;
      }
    }
    return prefixHit;
  }

  Future<void> clear() async {
    _cached = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheAtKey);
    } catch (_) {}
  }

  Future<EmployeeMarketingScope?> _fromCache() async {
    if (_cached != null) return _cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      final at = prefs.getInt(_cacheAtKey) ?? 0;
      if (raw == null || raw.isEmpty) return null;
      if (DateTime.now().millisecondsSinceEpoch - at >= _cacheTtl.inMilliseconds) {
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final scope = EmployeeMarketingScope.fromJson(decoded);
      _cached = scope;
      return scope;
    } catch (_) {
      return null;
    }
  }

  Future<void> _persist(EmployeeMarketingScope scope) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(scope.toJson()));
      await prefs.setInt(_cacheAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // In-memory caching still applies for this session.
    }
  }
}