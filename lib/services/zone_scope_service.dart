import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/marketing_demo_masters.dart';
import '../models/marketing_models.dart';
import '../models/zone_models.dart';
import '../models/zone_scope.dart';
import 'auth_service.dart';
import 'marketing_service.dart';
import 'sales_service.dart';

/// Resolves the zones the logged-in employee is assigned to.
///
/// The HRM profile carries only `user.zoneId` — a jsonb array of ids with no
/// names and no FK. The names and districts live in the Sales zone master, so
/// the two are joined here once per session and the result is reused by every
/// marketing list, form picker and dealer dropdown.
///
/// Every failure path resolves to `null` — an unreachable zone master must
/// degrade to the previous unfiltered behaviour, never to an empty screen.
class ZoneScopeService {
  ZoneScopeService._();
  static final ZoneScopeService instance = ZoneScopeService._();

  static const String _cacheKey = 'zone_scope_json';
  static const String _cacheAtKey = 'zone_scope_resolved_at_ms';

  /// Zone assignments change rarely; a day-old resolution is fine and spares
  /// the app a round-trip on every cold start.
  static const Duration _cacheTtl = Duration(hours: 24);

  final AuthService _authService = AuthService();
  final SalesService _salesService = SalesService();

  ZoneScope? _cached;
  bool _resolving = false;

  ZoneScope? get cached => _cached;

  /// The employee's zone scope, or `null` when they hold no zones or the zone
  /// master is unreachable.
  Future<ZoneScope?> load({bool forceRefresh = false}) async {
    if (!forceRefresh && _cached != null) {
      return _cached;
    }

    if (!forceRefresh) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      final resolvedAt = prefs.getInt(_cacheAtKey) ?? 0;
      if (raw != null && raw.isNotEmpty && _isFresh(resolvedAt)) {
        final restored = _decode(raw);
        if (restored != null) {
          _cached = restored;
          return restored;
        }
      }
    }

    final profile = _authService.cachedProfileOrNull ??
        await _authService.getCurrentUserProfile();
    final zoneIds = profile?.zoneIds ?? const <int>[];
    if (zoneIds.isEmpty) {
      await clear();
      return null;
    }

    if (_resolving) return _cached;
    _resolving = true;

    try {
      final result = await _salesService.fetchZoneList(
        forceRefresh: forceRefresh,
      );
      if (!result.success) {
        // A failed refresh must not discard a scope we already resolved.
        return _cached ?? _restoreFromDisk();
      }

      final scope = ZoneScope.fromZones(zoneIds, result.data ?? const []);
      if (scope.isEmpty) {
        await clear();
        return null;
      }

      _cached = scope;
      await _persist(scope);
      return scope;
    } catch (_) {
      return _cached ?? _restoreFromDisk();
    } finally {
      _resolving = false;
    }
  }

  /// Drops the resolved scope. Called on login and logout so a different user's
  /// zones can never leak into the previous one's session.
  Future<void> clear() async {
    _cached = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheAtKey);
    } catch (_) {}
  }

  Future<ZoneScope?> _restoreFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return null;
      return _decode(raw);
    } catch (_) {
      return null;
    }
  }

  bool _isFresh(int resolvedAtMs) {
    if (resolvedAtMs <= 0) return false;
    final age = DateTime.now().millisecondsSinceEpoch - resolvedAtMs;
    return age >= 0 && age < _cacheTtl.inMilliseconds;
  }

  ZoneScope? _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final scope = ZoneScope.fromJson(decoded);
      return scope.isEmpty ? null : scope;
    } catch (_) {
      return null;
    }
  }

  Future<void> _persist(ZoneScope scope) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(scope.toJson()));
      await prefs.setInt(_cacheAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // In-memory caching still applies for this session.
    }
  }

  /// The employee's zone ids, used by the forms to pre-seed a zone picker.
  Future<List<int>> currentZoneIds() async {
    final profile = _authService.cachedProfileOrNull ??
        await _authService.getCurrentUserProfile();
    return profile?.zoneIds ?? const <int>[];
  }

  /// Zone picker options for the market and party forms.
  ///
  /// Sourced from the Sales zone master so the picker's ids and names are the
  /// authoritative ones, with the demo zones as a fallback when the master is
  /// unreachable.
  Future<List<MarketingDemoNamed>> loadZoneOptions() async {
    final result = await SalesService().fetchZoneList();
    final zones = result.success ? (result.data ?? const <SalesZone>[]) : const <SalesZone>[];
    if (zones.isEmpty) return MarketingDemoMasters.zones;
    return zones
        .map((z) => MarketingDemoNamed(id: z.id, name: z.zoneName))
        .toList();
  }

  /// District names for every zone, keyed by lowercase zone name.
  ///
  /// Used by the party form to offer only the markets that sit inside the
  /// zone the user just picked. Keyed by name because zone ids are not
  /// comparable across systems.
  Future<Map<String, Set<String>>> loadZoneDistricts() async {
    final result = await SalesService().fetchZoneList();
    final zones =
        result.success ? (result.data ?? const <SalesZone>[]) : const <SalesZone>[];
    if (zones.isEmpty) return const {};

    final byZone = <String, Set<String>>{};
    for (final zone in zones) {
      byZone[zone.zoneName.toLowerCase()] =
          zone.districts.map((d) => d.name.toLowerCase()).toSet();
    }
    return byZone;
  }

  /// Districts keyed by market id.
  ///
  /// A party carries no district of its own, so its zone has to be inferred
  /// from the market it sits in. Fetching the market list here keeps that
  /// lookup in one place instead of duplicating the request per screen.
  Future<Map<int, String>> loadMarketDistricts() async {
    final result = await MarketingService().listMarkets();
    if (!result.success) return const {};

    final districts = <int, String>{};
    for (final market in result.data ?? const <Market>[]) {
      final district = market.district?.trim();
      if (district != null && district.isNotEmpty) {
        districts[market.id] = district;
      }
    }
    return districts;
  }
}
