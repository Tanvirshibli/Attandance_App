/// Compile-time backend URL configuration for the attendance app.
///
/// Production (default): no dart-defines required.
/// Development (Cloudflare tunnel on this PC): pass
/// `--dart-define=USE_LOCAL_TUNNEL_BACKENDS=true`.
class AppConfig {
  AppConfig._();

  static const bool useLocalTunnelBackends = bool.fromEnvironment(
    'USE_LOCAL_TUNNEL_BACKENDS',
    defaultValue: false,
  );

  /// When true (default), Sales Info uses local demo data until the external
  /// sales backend is ready. Pass `--dart-define=USE_SALES_DEMO_DATA=false` to
  /// call live sales endpoints.
  static const bool useSalesDemoData = bool.fromEnvironment(
    'USE_SALES_DEMO_DATA',
    defaultValue: true,
  );

  /// When true (default), Payments hub uses local demo data shaped like HRM
  /// resources. Pass `--dart-define=USE_PAYMENT_DEMO_DATA=false` with
  /// `payment.enabled` to hit live pphl_erp payment APIs.
  static const bool usePaymentDemoData = bool.fromEnvironment(
    'USE_PAYMENT_DEMO_DATA',
    defaultValue: true,
  );

  /// HRM / pphl_erp tunnel — auth, profile, face registration, leaves, holidays, sales, payments, etc.
  static const String _localTunnelBackendBaseUrl =
      'https://hrm.peoplesitsolution.online';

  /// ZKTeco local tunnel — attendance machine comms, mobile attendance requests.
  static const String _localTunnelAttendanceBaseUrl =
      'https://zktecolocal.peoplesitsolution.online';

  static const String _productionBackendBaseUrl =
      'https://hrm.peoplesitsolution.com';
  static const String _productionAttendanceBaseUrl =
      'https://zkteco.peoplesitsolution.online';
  static const String _defaultFallbackBaseUrls = '';

  /// Legacy single-base override; used for auth/ERP when set.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static const String authApiBaseUrl = String.fromEnvironment(
    'AUTH_API_BASE_URL',
    defaultValue: useLocalTunnelBackends
        ? _localTunnelBackendBaseUrl
        : _productionBackendBaseUrl,
  );

  static const String attendanceApiBaseUrl = String.fromEnvironment(
    'ATTENDANCE_API_BASE_URL',
    defaultValue: useLocalTunnelBackends
        ? _localTunnelAttendanceBaseUrl
        : _productionAttendanceBaseUrl,
  );

  /// Alias for ERP/HRM backend base URL (same as [authApiBaseUrl]).
  /// Use for future modules: leaves, holidays, sales, payment posts, etc.
  static String get backendApiBaseUrl => _resolvedAuthBase;

  static const String _apiBaseUrls = String.fromEnvironment(
    'API_BASE_URLS',
    defaultValue: _defaultFallbackBaseUrls,
  );

  static const String _attendanceApiBaseUrls = String.fromEnvironment(
    'ATTENDANCE_API_BASE_URLS',
    defaultValue: _defaultFallbackBaseUrls,
  );

  static String get _resolvedAuthBase {
    final legacy = apiBaseUrl.trim();
    if (legacy.isNotEmpty) {
      return legacy;
    }
    return authApiBaseUrl.trim();
  }

  static List<String> _expandPortAlternates(Iterable<String> bases) {
    final values = <String>{};
    for (final base in bases) {
      final trimmed = base.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      values.add(trimmed);

      final uri = Uri.tryParse(trimmed);
      if (uri == null || uri.host.isEmpty) {
        continue;
      }

      // Port alternates only apply to direct LAN/dev HTTP URLs, not HTTPS tunnels.
      if (uri.scheme == 'https') {
        continue;
      }

      final hasExplicitPort = trimmed.contains(':${uri.port}') &&
          (uri.port == 8000 || uri.port == 8080 || uri.port == 8095);
      if (!hasExplicitPort) {
        continue;
      }

      if (uri.port == 8000 || uri.port == 8080) {
        final alternatePort = uri.port == 8000 ? 8080 : 8000;
        values.add(uri.replace(port: alternatePort).toString());
      }
    }

    return values.toList();
  }

  static List<String> get authApiBaseUrlCandidates {
    final rawBases = <String>{
      _resolvedAuthBase,
      if (_apiBaseUrls.trim().isNotEmpty)
        ..._apiBaseUrls
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty),
    };

    return _expandPortAlternates(rawBases);
  }

  static List<String> get attendanceApiBaseUrlCandidates {
    final rawBases = <String>{
      attendanceApiBaseUrl.trim(),
      if (_attendanceApiBaseUrls.trim().isNotEmpty)
        ..._attendanceApiBaseUrls
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty),
    };

    return _expandPortAlternates(rawBases);
  }

  static List<String> get loginUrls =>
      authApiBaseUrlCandidates.map((base) => '$base/api/v1/a/login').toList();

  static List<String> get currentUserUrls => authApiBaseUrlCandidates
      .map((base) => '$base/api/v1/get-my-info')
      .toList();

  static List<String> get logoutUrls =>
      authApiBaseUrlCandidates.map((base) => '$base/api/v1/logout').toList();

  static List<String> get attendanceRequestUrls => attendanceApiBaseUrlCandidates
      .map((base) => '$base/api/v1/mobile/attendance-requests')
      .toList();

  static List<String> get faceRegistrationUrls => authApiBaseUrlCandidates
      .map((base) => '$base/api/v1/mobile/face-registration')
      .toList();

  /// JWT-scoped mobile attendance on HRM backend (preferred when logged in).
  static List<String> get mobileAttendanceJwtUrls => authApiBaseUrlCandidates
      .map((base) => '$base/api/v1/mobile/attendance-requests')
      .toList();

  static String get singleEmployeeAttendanceDetailsUrl =>
      '$backendApiBaseUrl/api/v1/single-employee-attendance-details';

  static String get leaveStocksUrl =>
      '$backendApiBaseUrl/api/v1/new-leave-stocks';

  static String get leavesUrl => '$backendApiBaseUrl/api/v1/leaves';

  static String get leaveTypesUrl => '$backendApiBaseUrl/api/v1/leavetypes';

  static String get payLoanUrl => '$backendApiBaseUrl/api/v1/get/pay-loan';

  static String get payLoanStoreUrl =>
      '$backendApiBaseUrl/api/v1/pay-loan/store';

  static String get payrollUrl => '$backendApiBaseUrl/api/v1/payroll';

  static String get loansEmployeeUrl =>
      '$backendApiBaseUrl/api/v1/loans-employee';

  static String get salesEmployeeListUrl =>
      '$backendApiBaseUrl/api/get-sales-employee-list';

  /// Reserved for future backend geo upload — not implemented yet.
  static String get geoLocationUploadUrl =>
      '$backendApiBaseUrl/api/v1/mobile/geo-location';

  static const int geoTrackingIntervalMinutes = 5;
}
