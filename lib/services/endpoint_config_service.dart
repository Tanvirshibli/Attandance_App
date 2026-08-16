import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/endpoint_config.dart';

class EndpointConfigService {
  EndpointConfigService._();
  static final EndpointConfigService instance = EndpointConfigService._();

  static const String bootstrapBaseUrlKey = 'bootstrap_zkteco_base_url';
  static const String configCacheKey = 'endpoint_config_json';
  static const String configFetchedAtKey = 'endpoint_config_fetched_at_ms';

  EndpointConfig? _cached;

  Future<bool> hasBootstrapUrl() async {
    final url = await getBootstrapBaseUrl();
    return url != null && url.isNotEmpty;
  }

  Future<String?> getBootstrapBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(bootstrapBaseUrlKey)?.trim();
    if (stored != null && stored.isNotEmpty) {
      return _normalizeBase(stored);
    }

    // Compile-time fallback for existing tunnel/production builds.
    if (AppConfig.attendanceApiBaseUrl.trim().isNotEmpty) {
      return _normalizeBase(AppConfig.attendanceApiBaseUrl);
    }

    return null;
  }

  Future<void> setBootstrapBaseUrl(String baseUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(bootstrapBaseUrlKey, _normalizeBase(baseUrl));
    _cached = null;
  }

  Future<EndpointConfig?> getConfig({bool forceRefresh = false}) async {
    if (!forceRefresh && _cached != null) {
      return _cached;
    }

    if (!forceRefresh) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(configCacheKey);
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            _cached = EndpointConfig.fromJson(decoded);
            return _cached;
          }
        } catch (_) {}
      }
    }

    return refreshConfig();
  }

  Future<EndpointConfig?> refreshConfig() async {
    final base = await getBootstrapBaseUrl();
    if (base == null || base.isEmpty) {
      return _cached = _fallbackConfig();
    }

    final url = '$base/api/v1/mobile/app-config';

    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'PPHLAttendance/2.1 (Android; Flutter)',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 304 && _cached != null) {
        return _cached;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final config = EndpointConfig.fromJson(decoded);
          _cached = config;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(configCacheKey, jsonEncode(decoded));
          await prefs.setInt(
            configFetchedAtKey,
            DateTime.now().millisecondsSinceEpoch,
          );
          return config;
        }
      }
    } catch (_) {}

    return _cached ??= _fallbackConfig();
  }

  Future<String?> resolveUrl(String key) async {
    final config = await getConfig();
    final dynamicUrl = config?.urlFor(key);
    if (dynamicUrl != null && dynamicUrl.isNotEmpty) {
      return dynamicUrl;
    }
    return _fallbackUrl(key);
  }

  Future<List<String>> resolveUrlCandidates(String key) async {
    final primary = await resolveUrl(key);
    if (primary == null || primary.isEmpty) {
      return const [];
    }
    return [primary];
  }

  Future<bool> isFeatureEnabled(String key, {bool defaultValue = false}) async {
    final config = await getConfig();
    return config?.isFeatureEnabled(key, defaultValue: defaultValue) ??
        defaultValue;
  }

  Future<int> geoIntervalMinutes() async {
    final config = await getConfig();
    return config?.geoIntervalMinutes(fallback: AppConfig.geoTrackingIntervalMinutes) ??
        AppConfig.geoTrackingIntervalMinutes;
  }

  Future<String?> hrmBaseUrl() async {
    final config = await getConfig();
    return config?.bases['hrm'] ?? AppConfig.backendApiBaseUrl;
  }

  Future<String?> zktecoBaseUrl() async {
    final config = await getConfig();
    return config?.bases['zkteco'] ?? AppConfig.attendanceApiBaseUrl;
  }

  EndpointConfig _fallbackConfig() {
    final hrm = AppConfig.backendApiBaseUrl;
    final zkteco = AppConfig.attendanceApiBaseUrl;

    EndpointDefinition ep(String method, String path, String backend) {
      final base = backend == 'hrm' ? hrm : zkteco;
      return EndpointDefinition(
        method: method,
        url: '$base$path',
        backend: backend,
      );
    }

    final sales = AppConfig.salesApiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final transport =
        AppConfig.transportApiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');

    return EndpointConfig(
      version: 0,
      bases: {
        'hrm': hrm,
        'zkteco': zkteco,
        'sales': sales,
        'transport': transport,
      },
      features: {
        'sales.enabled': true,
        'payment.enabled': true,
        'vehicle.enabled': true,
        'geo.tracking.enabled': true,
        'marketing.enabled': true,
        'interval_minutes': AppConfig.geoTrackingIntervalMinutes,
      },
      endpoints: {
        'auth.login': ep('POST', '/api/v1/a/login', 'hrm'),
        'auth.logout': ep('GET', '/api/v1/logout', 'hrm'),
        'auth.profile': ep('GET', '/api/v1/get-my-info', 'hrm'),
        'auth.refresh': ep('POST', '/api/v1/refresh', 'hrm'),
        'face.registration': ep('POST', '/api/v1/mobile/face-registration', 'hrm'),
        'face.registration.get': ep('GET', '/api/v1/mobile/face-registration', 'hrm'),
        'attendance.list': ep('GET', '/api/v1/mobile/attendance-requests', 'zkteco'),
        'attendance.punch': ep('POST', '/api/v1/mobile/attendance-requests', 'zkteco'),
        'attendance.summary': ep('GET', '/api/v1/single-employee-attendance-details', 'hrm'),
        'leave.balance': ep('GET', '/api/v1/new-leave-stocks', 'hrm'),
        'leave.history': ep('GET', '/api/v1/leaves', 'hrm'),
        'leave.types': ep('GET', '/api/v1/leavetypes', 'hrm'),
        'leave.newTypes': ep('GET', '/api/v1/new-leave-types', 'hrm'),
        'leave.apply': ep('POST', '/api/v1/leaves', 'hrm'),
        'leave.holidays': ep('GET', '/api/v1/mobile/holidays', 'hrm'),
        'geo.upload': ep('POST', '/api/v1/mobile/geo-location', 'zkteco'),
        'geo.history': ep('GET', '/api/v1/mobile/geo-location', 'zkteco'),
        'geo.fcm_token': ep('POST', '/api/v1/mobile/fcm-token', 'zkteco'),
        'payment.loans': ep('GET', '/api/v1/loans-employee', 'hrm'),
        'payment.loan.detail': ep('GET', '/api/v1/loan', 'hrm'),
        'payment.post': ep('POST', '/api/v1/pay-loan/store', 'hrm'),
        'payment.history': ep('GET', '/api/v1/get/pay-loan', 'hrm'),
        'payment.payroll': ep('GET', '/api/v1/payroll', 'hrm'),
        'payment.payroll.detail': ep('GET', '/api/v1/payroll', 'hrm'),
        'payment.pf': ep('GET', '/api/v1/providentfunds-employee', 'hrm'),
        'payment.pf.history': ep('GET', '/api/v1/providentfunds', 'hrm'),
        'payment.mess': ep('GET', '/api/v1/mess-deposit-employee', 'hrm'),
        'payment.facility': ep('GET', '/api/v1/facility-employee', 'hrm'),
        'payment.authWise': EndpointDefinition(
          method: 'GET',
          url: '$sales/api/auth-wise-payments',
          backend: 'sales',
        ),
        'payment.authWisePost': EndpointDefinition(
          method: 'POST',
          url: '$sales/api/auth-wise-payments',
          backend: 'sales',
        ),
        'payment.setupData': EndpointDefinition(
          method: 'GET',
          url: '$sales/api/payment-setup-data',
          backend: 'sales',
        ),
        'sales.eligibility': ep('GET', '/api/get-sales-employee-list', 'hrm'),
        'sales.personSales': EndpointDefinition(
          method: 'GET',
          url: '$sales/api/sales-person-sales',
          backend: 'sales',
        ),
        // Legacy keys retained for remote-config compatibility (unused by UI).
        'sales.overview': EndpointDefinition(
          method: 'GET',
          url: '$sales/api/sales-person-sales',
          backend: 'sales',
        ),
        'sales.list': EndpointDefinition(
          method: 'GET',
          url: '$sales/api/sales-person-sales',
          backend: 'sales',
        ),
        'sales.create': EndpointDefinition(
          method: 'POST',
          url: '$sales/api/sales-person-sales',
          backend: 'sales',
        ),
        'sales.booking.create': EndpointDefinition(
          method: 'POST',
          url: '$sales/api/booking-person-books',
          backend: 'sales',
        ),
        'sales.booking.formData': EndpointDefinition(
          method: 'GET',
          url: '$sales/api/booking-person-books/form-data',
          backend: 'sales',
        ),
        'sales.allDealers': EndpointDefinition(
          method: 'GET',
          url: '$sales/api/all-dealer-lists',
          backend: 'sales',
        ),
        'vehicle.list': EndpointDefinition(
          method: 'GET',
          url: '$transport/api/get-vehicle-active-list',
          backend: 'transport',
        ),
        'vehicle.maintenance': EndpointDefinition(
          method: 'GET',
          url: '$transport/api/get-vehicle-m-history',
          backend: 'transport',
        ),
        'vehicle.trips': EndpointDefinition(
          method: 'GET',
          url: '$transport/api/get-trips-list',
          backend: 'transport',
        ),
        'marketing.markets': ep(
          'GET',
          '/api/v1/mobile/marketing/markets',
          'zkteco',
        ),
        'marketing.market.create': ep(
          'POST',
          '/api/v1/mobile/marketing/markets',
          'zkteco',
        ),
        'marketing.parties': ep(
          'GET',
          '/api/v1/mobile/marketing/parties',
          'zkteco',
        ),
        'marketing.party.create': ep(
          'POST',
          '/api/v1/mobile/marketing/parties',
          'zkteco',
        ),
        'marketing.visits': ep(
          'GET',
          '/api/v1/mobile/marketing/visits',
          'zkteco',
        ),
        'marketing.visit.create': ep(
          'POST',
          '/api/v1/mobile/marketing/visits',
          'zkteco',
        ),
        'marketing.visit.checkIn': ep(
          'POST',
          '/api/v1/mobile/marketing/visits',
          'zkteco',
        ),
        'marketing.visit.checkOut': ep(
          'POST',
          '/api/v1/mobile/marketing/visits',
          'zkteco',
        ),
        'marketing.surveys': ep(
          'GET',
          '/api/v1/mobile/marketing/farm-surveys',
          'zkteco',
        ),
        'marketing.survey.create': ep(
          'POST',
          '/api/v1/mobile/marketing/farm-surveys',
          'zkteco',
        ),
        'marketing.followups': ep(
          'GET',
          '/api/v1/mobile/marketing/followups',
          'zkteco',
        ),
        'marketing.followup.create': ep(
          'POST',
          '/api/v1/mobile/marketing/followups',
          'zkteco',
        ),
        'marketing.attachments': ep(
          'POST',
          '/api/v1/mobile/marketing/attachments',
          'zkteco',
        ),
      },
    );
  }

  String? _fallbackUrl(String key) {
    return _fallbackConfig().urlFor(key);
  }

  String _normalizeBase(String base) {
    return base.trim().replaceAll(RegExp(r'/+$'), '');
  }
}
