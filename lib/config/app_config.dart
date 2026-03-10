class AppConfig {
  AppConfig._();

  static const String _defaultBaseUrl = 'https://hrm.peoplesitsolution.com';
  static const String _defaultFallbackBaseUrls = '';

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _defaultBaseUrl,
  );

  static const String _apiBaseUrls = String.fromEnvironment(
    'API_BASE_URLS',
    defaultValue: _defaultFallbackBaseUrls,
  );

  static List<String> get apiBaseUrlCandidates {
    final rawBases = <String>{
      apiBaseUrl.trim(),
      if (_apiBaseUrls.trim().isNotEmpty)
        ..._apiBaseUrls
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty),
    };

    final values = <String>{};
    for (final base in rawBases) {
      values.add(base);

      final uri = Uri.tryParse(base);
      if (uri == null || uri.host.isEmpty) {
        continue;
      }

      final hasExplicitPort = base.contains(':${uri.port}') &&
          (uri.port == 8000 || uri.port == 8080);
      if (!hasExplicitPort) {
        continue;
      }

      final alternatePort = uri.port == 8000 ? 8080 : 8000;
      final alternateUri = uri.replace(port: alternatePort);
      values.add(alternateUri.toString());
    }

    return values.toList();
  }

  static List<String> get loginUrls =>
      apiBaseUrlCandidates.map((base) => '$base/api/v1/a/login').toList();

  static List<String> get currentUserUrls =>
      apiBaseUrlCandidates.map((base) => '$base/api/v1/get-my-info').toList();

  static List<String> get logoutUrls =>
      apiBaseUrlCandidates.map((base) => '$base/api/v1/logout').toList();

  static List<String> get attendanceRequestUrls => apiBaseUrlCandidates
      .map((base) => '$base/api/v1/mobile/attendance-requests')
      .toList();

  static List<String> get faceRegistrationUrls => apiBaseUrlCandidates
      .map((base) => '$base/api/v1/mobile/face-registration')
      .toList();
}
