import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'auth_service.dart';
import 'endpoint_config_service.dart';

/// One HTTP outcome, so callers can tell a server rejection (which carries a
/// message worth showing) from an unreachable host (null response).
class BiometricHttpResult {
  const BiometricHttpResult({required this.statusCode, required this.body});

  final int statusCode;
  final Map<String, dynamic> body;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

class BiometricChallenge {
  const BiometricChallenge({required this.nonce, this.expiresAt});

  final String nonce;
  final String? expiresAt;
}

class BiometricPunchAuthorization {
  const BiometricPunchAuthorization({
    required this.authorizationId,
    this.expiresAt,
  });

  final String authorizationId;
  final String? expiresAt;
}

class BiometricCredentialRecord {
  const BiometricCredentialRecord({
    required this.credentialId,
    this.deviceIdentifier,
    this.status,
    this.enrolledAt,
    this.lastUsedAt,
  });

  final String credentialId;
  final String? deviceIdentifier;
  final String? status;
  final String? enrolledAt;
  final String? lastUsedAt;

  static BiometricCredentialRecord? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = raw['credentialId']?.toString() ?? raw['credential_id']?.toString();
    if (id == null || id.isEmpty) return null;
    return BiometricCredentialRecord(
      credentialId: id,
      deviceIdentifier: raw['deviceIdentifier']?.toString() ??
          raw['device_identifier']?.toString(),
      status: raw['status']?.toString(),
      enrolledAt:
          raw['enrolledAt']?.toString() ?? raw['enrolled_at']?.toString(),
      lastUsedAt:
          raw['lastUsedAt']?.toString() ?? raw['last_used_at']?.toString(),
    );
  }
}

class BiometricPreferencesData {
  const BiometricPreferencesData({
    required this.loginFace,
    required this.loginFingerprint,
    required this.checkinFace,
    required this.checkinFingerprint,
  });

  /// Every switch off, matching the server's own defaults
  /// (`MobileBiometricCredential::preferencesFrom`), so an app that has never
  /// synced claims nothing the backend would refuse.
  const BiometricPreferencesData.defaults()
      : loginFace = false,
        loginFingerprint = false,
        checkinFace = false,
        checkinFingerprint = false;

  final bool loginFace;
  final bool loginFingerprint;
  final bool checkinFace;
  final bool checkinFingerprint;

  BiometricPreferencesData copyWith({
    bool? loginFace,
    bool? loginFingerprint,
    bool? checkinFace,
    bool? checkinFingerprint,
  }) {
    return BiometricPreferencesData(
      loginFace: loginFace ?? this.loginFace,
      loginFingerprint: loginFingerprint ?? this.loginFingerprint,
      checkinFace: checkinFace ?? this.checkinFace,
      checkinFingerprint: checkinFingerprint ?? this.checkinFingerprint,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'login': {'face': loginFace, 'fingerprint': loginFingerprint},
      'checkin': {'face': checkinFace, 'fingerprint': checkinFingerprint},
    };
  }

  static BiometricPreferencesData? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final login = raw['login'];
    final checkin = raw['checkin'];
    if (login is! Map && checkin is! Map) return null;

    bool read(Object? source, String key, bool fallback) {
      if (source is! Map) return fallback;
      final value = source[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) return value == 'true' || value == '1';
      return fallback;
    }

    // Fallbacks are the server's defaults: everything off, so a preference the
    // payload omits can never read as "allowed" on the device alone.
    return BiometricPreferencesData(
      loginFace: read(login, 'face', false),
      loginFingerprint: read(login, 'fingerprint', false),
      checkinFace: read(checkin, 'face', false),
      checkinFingerprint: read(checkin, 'fingerprint', false),
    );
  }
}

class BiometricCredentialsSnapshot {
  const BiometricCredentialsSnapshot({
    required this.credentials,
    required this.preferences,
  });

  final List<BiometricCredentialRecord> credentials;
  final BiometricPreferencesData? preferences;
}

class BiometricApiService {
  BiometricApiService({AuthService? authService})
      : _authService = authService ?? AuthService();

  final AuthService _authService;
  final EndpointConfigService _configService = EndpointConfigService.instance;

  static const String _challengePath = '/api/v1/mobile/biometric-challenge';
  static const String _loginPath = '/api/v1/mobile/biometric-login';
  static const String _punchAuthorizationPath =
      '/api/v1/mobile/biometric-punch-authorization';
  static const String _credentialsPath = '/api/v1/mobile/biometric-credentials';
  static const String _preferencesPath =
      '/api/v1/mobile/biometric-preferences';

  Future<BiometricChallenge?> requestChallenge({
    required String credentialId,
    required String purpose,
  }) async {
    final response = await _send(
      method: 'POST',
      endpointKey: 'biometric.challenge',
      fallbackPath: _challengePath,
      body: {'credentialId': credentialId, 'purpose': purpose},
      // Public on the server, and the whole point is that it runs before any
      // session exists. Left authenticated, this returned null instantly on the
      // login screen (no token) and reported it as a network failure.
      authenticated: false,
    );
    if (response == null || !response.isSuccess) return null;

    final nonce = response.body['nonce']?.toString();
    if (nonce == null || nonce.isEmpty) return null;
    return BiometricChallenge(
      nonce: nonce,
      expiresAt: response.body['expires_at']?.toString() ??
          response.body['expiresAt']?.toString(),
    );
  }

  Future<BiometricHttpResult?> biometricLogin({
    required String credentialId,
    required String nonce,
    required String signature,
  }) {
    return _send(
      method: 'POST',
      endpointKey: 'biometric.login',
      fallbackPath: _loginPath,
      body: {
        'credentialId': credentialId,
        'nonce': nonce,
        'signature': signature,
      },
      authenticated: false,
    );
  }

  Future<BiometricPunchAuthorization?> requestPunchAuthorization({
    required String credentialId,
    required String nonce,
    required String signature,
    required String direction,
    required String deviceIdentifier,
  }) async {
    final response = await _send(
      method: 'POST',
      endpointKey: 'biometric.punchAuthorization',
      fallbackPath: _punchAuthorizationPath,
      body: {
        'credentialId': credentialId,
        'nonce': nonce,
        'signature': signature,
        'direction': direction,
        'deviceIdentifier': deviceIdentifier,
      },
    );
    if (response == null || !response.isSuccess) return null;

    final authorizationId = response.body['authorization_id']?.toString() ??
        response.body['authorizationId']?.toString();
    if (authorizationId == null || authorizationId.isEmpty) return null;
    return BiometricPunchAuthorization(
      authorizationId: authorizationId,
      expiresAt: response.body['expires_at']?.toString(),
    );
  }

  Future<BiometricCredentialsSnapshot?> fetchCredentials() async {
    final response = await _send(
      method: 'GET',
      endpointKey: 'biometric.credentials',
      fallbackPath: _credentialsPath,
    );
    if (response == null || !response.isSuccess) return null;

    final rawCredentials = response.body['credentials'];
    final credentials = <BiometricCredentialRecord>[];
    if (rawCredentials is List) {
      for (final entry in rawCredentials) {
        final record = BiometricCredentialRecord.fromJson(entry);
        if (record != null) credentials.add(record);
      }
    }

    return BiometricCredentialsSnapshot(
      credentials: credentials,
      preferences: BiometricPreferencesData.fromJson(
        response.body['preferences'],
      ),
    );
  }

  Future<bool> registerCredential({
    required String credentialId,
    required String publicKey,
    required String keyAlias,
    required String deviceIdentifier,
    required String deviceName,
    required String deviceModel,
    required String deviceVendor,
    required String appVersion,
    required String sdkVersion,
  }) async {
    final response = await _send(
      method: 'POST',
      endpointKey: 'biometric.credentials.register',
      alternateKey: 'biometric.credentials',
      fallbackPath: _credentialsPath,
      body: {
        'credentialId': credentialId,
        'publicKey': publicKey,
        'keyAlias': keyAlias,
        'algorithm': 'ES256',
        'deviceIdentifier': deviceIdentifier,
        'deviceName': deviceName,
        'deviceModel': deviceModel,
        'deviceVendor': deviceVendor,
        'appVersion': appVersion,
        'sdkVersion': sdkVersion,
      },
    );
    return response != null && response.isSuccess;
  }

  Future<bool> deleteCredential({required String credentialId}) async {
    if (credentialId.isEmpty) return false;
    final response = await _send(
      method: 'DELETE',
      endpointKey: 'biometric.credentials.delete',
      alternateKey: 'biometric.credentials',
      fallbackPath: _credentialsPath,
      appendPath: '/$credentialId',
      // A credential the server already dropped is gone either way, so its 404
      // is a result this caller needs rather than a host that does not serve
      // the path.
      returnNotFound: true,
    );
    return response != null &&
        (response.isSuccess || response.statusCode == 404);
  }

  /// Saves the four switches and returns the snapshot the server stored, so a
  /// caller can mirror exactly what the backend committed to — it may clamp a
  /// combination it will not accept. Null means the save did not land.
  Future<BiometricPreferencesData?> savePreferences(
    BiometricPreferencesData preferences,
  ) async {
    final response = await _send(
      method: 'PUT',
      endpointKey: 'biometric.preferences',
      fallbackPath: _preferencesPath,
      body: preferences.toJson(),
    );
    if (response == null || !response.isSuccess) return null;
    // A 2xx without a body still means the values were accepted as sent.
    return BiometricPreferencesData.fromJson(response.body['preferences']) ??
        preferences;
  }

  /// The GET and POST credential endpoints share one path, so a remotely
  /// published config may only carry the GET key; [alternateKey] lets the write
  /// calls reuse it before falling back to the compile-time base URLs.
  Future<List<String>> _urls(
    String endpointKey,
    String? alternateKey,
    String fallbackPath, {
    String appendPath = '',
  }) async {
    final urls = <String>{};
    for (final key in [endpointKey, ?alternateKey]) {
      final configured = await _configService.resolveUrl(key);
      if (configured != null && configured.isNotEmpty) {
        urls.add('$configured$appendPath');
      }
    }
    for (final base in AppConfig.authApiBaseUrlCandidates) {
      if (base.isEmpty) continue;
      urls.add('$base$fallbackPath$appendPath');
    }
    return urls.toList();
  }

  Future<BiometricHttpResult?> _send({
    required String method,
    required String endpointKey,
    required String fallbackPath,
    Map<String, dynamic>? body,
    bool authenticated = true,
    String appendPath = '',
    String? alternateKey,
    // Opt-in: hand a 404 back to the caller instead of walking on to the next
    // candidate. Delete wants it (404 = already gone, which is the success
    // case); every other call still treats 404 as "wrong host, keep looking".
    bool returnNotFound = false,
  }) async {
    var token = authenticated ? await _authService.getToken() : null;
    if (authenticated && (token == null || token.isEmpty)) return null;

    for (final url in await _urls(
      endpointKey,
      alternateKey,
      fallbackPath,
      appendPath: appendPath,
    )) {
      try {
        var response = await _request(method, url, body: body, token: token);
        if (response.statusCode == 404 && !returnNotFound) continue;

        if (response.statusCode == 401 && authenticated) {
          if (!await _authService.refreshToken()) return null;
          final refreshedToken = await _authService.getToken();
          if (refreshedToken == null || refreshedToken.isEmpty) return null;
          token = refreshedToken;
          response =
              await _request(method, url, body: body, token: refreshedToken);
          if (response.statusCode == 401) return null;
        }

        return BiometricHttpResult(
          statusCode: response.statusCode,
          body: _decodeMap(response.body),
        );
      } on TimeoutException {
        continue;
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  Future<http.Response> _request(
    String method,
    String url, {
    Map<String, dynamic>? body,
    String? token,
  }) {
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': 'PPHLAttendance/2.5 (Android; Flutter)',
      if (body != null) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    final uri = Uri.parse(url);
    final encoded = body == null ? null : jsonEncode(body);

    switch (method) {
      case 'POST':
        return http
            .post(uri, headers: headers, body: encoded)
            .timeout(const Duration(seconds: 20));
      case 'PUT':
        return http
            .put(uri, headers: headers, body: encoded)
            .timeout(const Duration(seconds: 20));
      case 'DELETE':
        return http
            .delete(uri, headers: headers, body: encoded)
            .timeout(const Duration(seconds: 20));
      default:
        return http.get(uri, headers: headers).timeout(
              const Duration(seconds: 15),
            );
    }
  }

  Map<String, dynamic> _decodeMap(String responseBody) {
    if (responseBody.isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}
