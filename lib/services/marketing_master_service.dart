import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/marketing_demo_masters.dart';
import '../models/booking_form_data_models.dart';
import '../models/marketing_models.dart';
import 'marketing_service.dart';
import 'sales_service.dart';

/// The company / sector / market lists the marketing forms cascade through.
///
/// The officer picks a company, the sector list narrows to that company's own
/// sectors, and the market list narrows to the chosen sector's markets. Nothing
/// here is derived from the employee's zone — zone is a fact about the record
/// shown read-only, and narrowing their choices by it only hid options they
/// legitimately needed.
///
/// Companies and sectors come from the Sales booking form-data master, where
/// every sector row carries a real `companyId`. That edge is the whole cascade;
/// there is no local org master and no sync behind it.
class MarketingMasterService {
  MarketingMasterService._();
  static final MarketingMasterService instance = MarketingMasterService._();

  static const String _cacheKey = 'marketing_masters_json';
  static const String _cacheAtKey = 'marketing_masters_resolved_at_ms';

  /// These masters change slowly; a day-old copy spares the app a round-trip on
  /// every cold start.
  static const Duration _cacheTtl = Duration(hours: 24);

  final SalesService _salesService = SalesService();
  final MarketingService _marketingService = MarketingService();

  List<BookingFormCompany>? _companies;
  List<BookingFormSector>? _sectors;
  List<Market>? _markets;

  /// Every approved company. Empty when the master is unreachable, which shows
  /// an empty picker rather than hanging the form.
  Future<List<BookingFormCompany>> companies({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _companies != null) return _companies!;

    final restored = await _restore(forceRefresh);
    if (restored != null) {
      _companies = restored.companies;
      _sectors = restored.sectors;
      return _companies!;
    }

    try {
      final result = await _salesService.fetchBookingFormData();
      if (!result.success) return _companies ?? const [];

      final data = result.data;
      _companies = MarketingDemoMasters.companiesOr(
        data?.companies ?? const [],
      );
      _sectors = MarketingDemoMasters.sectorsOr(data?.sectors ?? const []);
      await _persist(_companies!, _sectors!);
      return _companies!;
    } catch (_) {
      return _companies ?? const [];
    }
  }

  /// The sectors belonging to [companyId].
  ///
  /// Returns every sector when [companyId] is null, so the caller can show an
  /// unfiltered list before a company has been chosen. A sector with no company
  /// of its own is kept in that unfiltered case and excluded from every
  /// company's own list — it belongs to nobody in particular.
  Future<List<BookingFormSector>> sectorsForCompany(
    int? companyId, {
    bool forceRefresh = false,
  }) async {
    await companies(forceRefresh: forceRefresh);
    final sectors = _sectors ?? const <BookingFormSector>[];

    return filterSectorsForCompany(sectors, companyId);
  }

  /// Pure filter behind [sectorsForCompany], so the cascade rule is testable
  /// without a network round-trip.
  static List<BookingFormSector> filterSectorsForCompany(
    List<BookingFormSector> sectors,
    int? companyId,
  ) {
    if (companyId == null || companyId <= 0) {
      return sectors.where((s) => s.id > 0).toList();
    }

    return sectors.where((s) => s.id > 0 && s.companyId == companyId).toList();
  }

  /// The markets belonging to [sectorId].
  ///
  /// Every market when [sectorId] is null. Markets recorded before a sector was
  /// chosen carry no `sectorId`; they are kept in the unfiltered case only, so a
  /// market that genuinely belongs to the chosen sector is never hidden.
  Future<List<Market>> marketsForSector(int? sectorId) async {
    await _loadMarkets();
    return filterMarketsForSector(_markets ?? const <Market>[], sectorId);
  }

  /// Pure filter behind [marketsForSector].
  static List<Market> filterMarketsForSector(
    List<Market> markets,
    int? sectorId,
  ) {
    if (sectorId == null || sectorId <= 0) {
      return markets;
    }

    return markets.where((m) => m.sectorId == sectorId).toList();
  }

  Future<void> _loadMarkets() async {
    if (_markets != null) return;

    try {
      final result = await _marketingService.listMarkets();
      if (result.success) {
        _markets = result.data ?? const <Market>[];
      }
    } catch (_) {
      // Leave the cache null so a later screen can retry.
    }
  }

  Future<void> clear() async {
    _companies = null;
    _sectors = null;
    _markets = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheAtKey);
    } catch (_) {}
  }

  Future<_Masters?> _restore(bool forceRefresh) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return null;

      if (!forceRefresh) {
        final at = prefs.getInt(_cacheAtKey) ?? 0;
        final age = DateTime.now().millisecondsSinceEpoch - at;
        if (at <= 0 || age < 0 || age >= _cacheTtl.inMilliseconds) {
          return null;
        }
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final companies = (decoded['companies'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => BookingFormCompany.fromJson(Map<String, dynamic>.from(e)))
          .where((c) => c.id > 0)
          .toList();
      final sectors = (decoded['sectors'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => BookingFormSector.fromJson(Map<String, dynamic>.from(e)))
          .where((s) => s.id > 0)
          .toList();

      if (companies.isEmpty && sectors.isEmpty) return null;
      return _Masters(companies: companies, sectors: sectors);
    } catch (_) {
      return null;
    }
  }

  Future<void> _persist(
    List<BookingFormCompany> companies,
    List<BookingFormSector> sectors,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode({
          'companies': companies
              .map((c) => {'id': c.id, 'nameEn': c.nameEn, 'nameBn': c.nameBn})
              .toList(),
          'sectors': sectors
              .map(
                (s) => {'id': s.id, 'name': s.name, 'companyId': s.companyId},
              )
              .toList(),
        }),
      );
      await prefs.setInt(_cacheAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // In-memory caching still applies for this session.
    }
  }
}

class _Masters {
  const _Masters({required this.companies, required this.sectors});

  final List<BookingFormCompany> companies;
  final List<BookingFormSector> sectors;
}
