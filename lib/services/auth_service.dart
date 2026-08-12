import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/auth_user_profile.dart';
import 'endpoint_config_service.dart';
import 'fcm_wake_handler.dart';
import 'geo_tracking_service.dart';

class AuthResult {
  const AuthResult({
    required this.success,
    this.message,
    this.token,
  });

  final bool success;
  final String? message;
  final String? token;
}

class AuthService {
  static const String _tokenKey = 'auth_token';
  static const String _emailKey = 'auth_email';
  static const String _rememberKey = 'remember_me';
  static const Duration _profileCacheTtl = Duration(minutes: 20);

  final EndpointConfigService _configService = EndpointConfigService.instance;

  static Completer<bool>? _refreshCompleter;
  static AuthUserProfile? _cachedProfile;
  static DateTime? _cachedProfileAt;

  static void clearProfileCache() {
    _cachedProfile = null;
    _cachedProfileAt = null;
  }

  /// Cached profile when still within TTL (null if missing/stale).
  AuthUserProfile? get cachedProfileOrNull {
    if (_cachedProfile == null || _cachedProfileAt == null) {
      return null;
    }
    if (DateTime.now().difference(_cachedProfileAt!) > _profileCacheTtl) {
      return null;
    }
    return _cachedProfile;
  }

  int? get cachedCanonicalEmployeeId =>
      cachedProfileOrNull?.canonicalEmployeeId;

  Future<AuthResult> login({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    String? lastNetworkError;
    String? lastNetworkDetails;
    String? lastAttemptedLoginUrl;

    for (final loginUrl in await _loginUrls()) {
      lastAttemptedLoginUrl = loginUrl;
      try {
        final response = await http
            .post(
              Uri.parse(loginUrl),
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                // Helps Cloudflare/WAF distinguish app traffic from unknown bots.
                'User-Agent': 'PPHLAttendance/2.0 (Android; Flutter)',
              },
              body: jsonEncode({
                'email': email,
                'password': password,
              }),
            )
            .timeout(const Duration(seconds: 15));

        final data = _decodeMap(response.body);

        if (response.statusCode == 404) {
          continue;
        }

        if (response.statusCode == 200 && data['success'] == true) {
          final token = data['token']?.toString();
          if (token == null || token.isEmpty) {
            return const AuthResult(
              success: false,
              message: 'Authentication token missing in server response.',
            );
          }

          await _saveSession(
            token: token,
            email: email,
            rememberMe: rememberMe,
          );

          AuthService.clearProfileCache();
          try {
            await GeoTrackingService().clearHrmPause();
            await GeoTrackingService().ensureEnabledIfAllowed();
          } catch (_) {}

          // Register FCM token after session exists (no-op without Firebase config).
          try {
            await FcmWakeHandler.syncTokenWithBackend();
          } catch (_) {}

          return AuthResult(
            success: true,
            message: data['message']?.toString() ?? 'Login successful',
            token: token,
          );
        }

        if (response.statusCode == 429) {
          final retryAfter = response.headers['retry-after'];
          return AuthResult(
            success: false,
            message: retryAfter != null && retryAfter.isNotEmpty
                ? 'Too many requests. Please wait $retryAfter seconds and try again.'
                : 'Too many requests. Please wait a moment and try again.',
          );
        }

        if (response.statusCode == 422) {
          final errors = data['errors'];
          if (errors is Map<String, dynamic> && errors.isNotEmpty) {
            final first = errors.values.first;
            if (first is List && first.isNotEmpty) {
              return AuthResult(
                success: false,
                message: first.first.toString(),
              );
            }
          }
        }

        return AuthResult(
          success: false,
          message: data['message']?.toString() ??
              'Login failed (${response.statusCode}).',
        );
      } on TimeoutException catch (error) {
        lastNetworkError = 'Request timed out.';
        lastNetworkDetails = error.toString();
      } on SocketException catch (error) {
        lastNetworkError = 'Unable to connect to backend.';
        lastNetworkDetails =
            'SocketException: ${error.message} (osError=${error.osError?.errorCode ?? 'n/a'})';
      } on HandshakeException catch (error) {
        lastNetworkError = 'Secure connection failed.';
        lastNetworkDetails = 'HandshakeException: $error';
      } on http.ClientException catch (error) {
        lastNetworkError = 'HTTP client connection failed.';
        lastNetworkDetails = 'ClientException: ${error.message}';
      } catch (error) {
        lastNetworkError = 'Unexpected network error.';
        lastNetworkDetails = '$error';
      }
    }

    final baseUrls = AppConfig.authApiBaseUrlCandidates.join(', ');
    final networkReason = lastNetworkError ?? 'No reachable API login endpoint.';
    final devHint = AppConfig.useLocalTunnelBackends
        ? 'This build uses Cloudflare tunnel backends (USE_LOCAL_TUNNEL_BACKENDS=true). Ensure Cloudflared-hrmlocal is running and https://hrm.peoplesitsolution.online is healthy.'
        : 'Production builds target https://hrm.peoplesitsolution.com. For tunnel dev builds use --dart-define=USE_LOCAL_TUNNEL_BACKENDS=true.';
    return AuthResult(
      success: false,
      message:
          '$networkReason $devHint Tried bases: $baseUrls. Last URL: ${lastAttemptedLoginUrl ?? 'n/a'}. Details: ${lastNetworkDetails ?? 'n/a'}',
    );
  }

  /// Refresh JWT via HRM `auth.refresh` (`POST /api/v1/refresh`).
  /// Returns true when a new token was stored. Concurrent callers share one request.
  Future<bool> refreshToken() async {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    final completer = Completer<bool>();
    _refreshCompleter = completer;

    try {
      final result = await _refreshTokenOnce();
      completer.complete(result);
      return result;
    } catch (error) {
      completer.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }

  Future<bool> _refreshTokenOnce() async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      return false;
    }

    final refreshUrl = await _configService.resolveUrl('auth.refresh') ??
        '${AppConfig.backendApiBaseUrl}/api/v1/refresh';

    try {
      final response = await http
          .post(
            Uri.parse(refreshUrl),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
              'User-Agent': 'PPHLAttendance/2.1 (Android; Flutter)',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 429) {
        return false;
      }

      final data = _decodeMap(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }

      final newToken = data['token']?.toString();
      if (newToken == null || newToken.isEmpty) {
        return false;
      }

      final email = await getSavedEmail() ?? '';
      final rememberMe = await getRememberMe();
      await _saveSession(
        token: newToken,
        email: email,
        rememberMe: rememberMe,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<AuthUserProfile?> getCurrentUserProfile({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = cachedProfileOrNull;
      if (cached != null) {
        return cached;
      }
    }

    final initialToken = await getToken();
    if (initialToken == null || initialToken.isEmpty) {
      return null;
    }

    var token = initialToken;

    for (final url in await _profileUrls()) {
      try {
        var response = await _authorizedGet(url: url, token: token)
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 404) {
          continue;
        }

        if (response.statusCode == 429) {
          // Do not clear session on rate limit; return stale cache if any.
          return _cachedProfile;
        }

        if (response.statusCode == 401) {
          final refreshed = await refreshToken();
          if (!refreshed) {
            await logout(invalidateServerSession: false);
            return null;
          }
          final refreshedToken = await getToken();
          if (refreshedToken == null || refreshedToken.isEmpty) {
            return null;
          }
          token = refreshedToken;
          response = await _authorizedGet(url: url, token: token)
              .timeout(const Duration(seconds: 15));
          if (response.statusCode == 401) {
            await logout(invalidateServerSession: false);
            return null;
          }
          if (response.statusCode == 429) {
            return _cachedProfile;
          }
        }

        final data = _decodeMap(response.body);
        if (response.statusCode == 200 && data['user'] is Map<String, dynamic>) {
          final profile =
              AuthUserProfile.fromJson(data['user'] as Map<String, dynamic>);
          _cachedProfile = profile;
          _cachedProfileAt = DateTime.now();
          return profile;
        }
      } catch (_) {
        continue;
      }
    }

    return _cachedProfile;
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

  Future<void> _saveSession({
    required String token,
    required String email,
    required bool rememberMe,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_emailKey, email);
    await prefs.setBool(_rememberKey, rememberMe);
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    return token != null && token.isNotEmpty;
  }

  Future<String?> getSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_emailKey);
  }

  Future<bool> getRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rememberKey) ?? true;
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<void> logout({bool invalidateServerSession = true}) async {
    final token = await getToken();

    if (invalidateServerSession && token != null && token.isNotEmpty) {
      for (final url in await _logoutUrls()) {
        try {
          final logoutUrl = Uri.parse(url).replace(queryParameters: {
            'token': token,
          });

          final response = await _authorizedGet(
            url: logoutUrl.toString(),
            token: token,
          ).timeout(const Duration(seconds: 12));

          if (response.statusCode != 404) {
            break;
          }
        } catch (_) {
          continue;
        }
      }
    }

    clearProfileCache();

    try {
      await GeoTrackingService().pauseForLogout();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_rememberKey);
    await prefs.remove(_emailKey);
  }

  Future<List<String>> _loginUrls() async {
    final dynamicUrl = await _configService.resolveUrl('auth.login');
    if (dynamicUrl != null && dynamicUrl.isNotEmpty) {
      return [dynamicUrl, ...AppConfig.loginUrls];
    }
    return AppConfig.loginUrls;
  }

  Future<List<String>> _profileUrls() async {
    final dynamicUrl = await _configService.resolveUrl('auth.profile');
    if (dynamicUrl != null && dynamicUrl.isNotEmpty) {
      return [dynamicUrl, ...AppConfig.currentUserUrls];
    }
    return AppConfig.currentUserUrls;
  }

  Future<List<String>> _logoutUrls() async {
    final dynamicUrl = await _configService.resolveUrl('auth.logout');
    if (dynamicUrl != null && dynamicUrl.isNotEmpty) {
      return [dynamicUrl, ...AppConfig.logoutUrls];
    }
    return AppConfig.logoutUrls;
  }

  Future<http.Response> _authorizedGet({
    required String url,
    required String token,
  }) {
    return http.get(
      Uri.parse(url),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
  }
}
