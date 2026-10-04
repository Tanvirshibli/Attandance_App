import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/auth_user_profile.dart';
import '../utils/user_facing_error.dart';
import 'endpoint_config_service.dart';
import 'fcm_wake_handler.dart';
import 'geo_tracking_service.dart';
import 'permission_service.dart';
import 'zone_scope_service.dart';

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

/// The outcome of one sweep across the candidate login URLs, plus whether the
/// failure was purely a slow connect — which is the only case worth retrying.
class _LoginPass {
  const _LoginPass({required this.result, this.onlyTimeouts = false});

  final AuthResult result;
  final bool onlyTimeouts;
}

class AuthService {
  static const String _tokenKey = 'auth_token';
  static const String _emailKey = 'auth_email';
  static const String _passwordKey = 'auth_password';
  static const String _rememberKey = 'remember_me';
  static const Duration _profileCacheTtl = Duration(minutes: 20);

  /// Login must tolerate a slow handshake. The production host has been
  /// measured taking ~20s to complete a TCP connect while still healthy, so
  /// the previous 15s ceiling killed requests that were about to succeed and
  /// reported them as "no internet".
  static const Duration _loginTimeout = Duration(seconds: 45);

  /// One retry, for a single attempt that timed out on a slow connect. A
  /// server that was merely slow will usually answer the second time.
  static const Duration _loginRetryDelay = Duration(seconds: 2);

  /// Ceiling for the whole login exchange including the retry, so the user is
  /// never left staring at a spinner indefinitely.
  static const Duration _loginOverallBudget = Duration(seconds: 80);

  /// Ceiling for authenticated reads (profile fetch, token refresh).
  ///
  /// The same production host that needed a 45s login ceiling has been
  /// measured taking 20s to complete a TCP connect on
  /// `/api/v1/get-my-info`, so a 15s read timeout failed requests the server
  /// was about to answer. The failure surfaced as "Could not load profile
  /// data" because a `TimeoutException` was swallowed by the same catch as a
  /// hard connection error.
  static const Duration _readTimeout = Duration(seconds: 45);

  final EndpointConfigService _configService = EndpointConfigService.instance;

  AuthService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// Injectable for tests, matching the `HrmApiClient` seam the other services
  /// already expose. Production always uses a real client.
  final http.Client _httpClient;

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
    final stopwatch = Stopwatch()..start();
    final loginUrls = await _loginUrls();

    // One extra pass, but only when the first pass failed purely on a slow
    // connect. The production host intermittently takes ~20s to complete a TCP
    // handshake, and the second attempt usually lands in under a second.
    AuthResult? outcome;
    var attempt = 0;
    while (true) {
      final pass = await _loginPass(
        loginUrls: loginUrls,
        email: email,
        password: password,
        rememberMe: rememberMe,
      );
      outcome = pass.result;
      final canRetry = pass.onlyTimeouts &&
          attempt == 0 &&
          stopwatch.elapsed < _loginOverallBudget;
      if (!canRetry) break;
      attempt++;
      await Future<void>.delayed(_loginRetryDelay);
    }

    return outcome;
  }

  /// One pass over every candidate login URL.
  Future<_LoginPass> _loginPass({
    required List<String> loginUrls,
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    String? lastNetworkError;
    String? lastNetworkDetails;
    String? lastAttemptedLoginUrl;
    Object? lastNetworkException;
    AuthResult? credentialRejection;
    var sawTimeout = false;

    for (final loginUrl in loginUrls) {
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
            .timeout(_loginTimeout);

        final data = _decodeMap(response.body);

        if (response.statusCode == 404) {
          continue;
        }

        // A URL that does not implement the HRM login contract (an HTML login
        // page, a 401 from a proxy, a misrouted host) must not be reported as a
        // bad password. Try the remaining candidates and only surface the
        // credential error if every URL genuinely rejected the credentials.
        if (response.statusCode == 401 || response.statusCode == 403) {
          credentialRejection = AuthResult(
            success: false,
            message: UserFacingError.forLogin(
              statusCode: response.statusCode,
              rawMessage:
                  data['message']?.toString() ?? data['error']?.toString(),
            ),
          );
          continue;
        }

        if (response.statusCode == 200 && data['success'] == true) {
          final token = data['token']?.toString();
          if (token == null || token.isEmpty) {
            return const _LoginPass(
              result: AuthResult(
                success: false,
                message: 'Authentication token missing in server response.',
              ),
            );
          }

          await _saveSession(
            token: token,
            email: email,
            password: password,
            rememberMe: rememberMe,
          );

          AuthService.clearProfileCache();
          // Zones and permissions belong to the user who just signed in; drop
          // anything left over from a previous session. Without the permission
          // clear, a user who signs out and another who signs in on the same
          // process would briefly see the first user's modules until this
          // account's profile landed.
          PermissionService.instance.clear();
          try {
            await ZoneScopeService.instance.clear();
          } catch (_) {}
          try {
            await GeoTrackingService().clearHrmPause();
            await GeoTrackingService().ensureEnabledIfAllowed();
          } catch (_) {}

          // Register FCM token after session exists (no-op without Firebase config).
          try {
            await FcmWakeHandler.syncTokenWithBackend();
          } catch (_) {}

          return _LoginPass(
            result: AuthResult(
              success: true,
              message: data['message']?.toString() ?? 'Login successful',
              token: token,
            ),
          );
        }

        if (response.statusCode == 429) {
          final retryAfter = response.headers['retry-after'];
          return _LoginPass(
            result: AuthResult(
              success: false,
              message: retryAfter != null && retryAfter.isNotEmpty
                  ? 'Too many requests. Please wait $retryAfter seconds and try again.'
                  : 'Too many requests. Please wait a moment and try again.',
            ),
          );
        }

        if (response.statusCode == 422) {
          return const _LoginPass(
            result: AuthResult(
              success: false,
              message: 'Please check your email and password format.',
            ),
          );
        }

        return _LoginPass(
          result: AuthResult(
            success: false,
            message: UserFacingError.forLogin(
              statusCode: response.statusCode,
              rawMessage:
                  data['message']?.toString() ?? data['error']?.toString(),
            ),
          ),
        );
      } on TimeoutException catch (error) {
        // A timeout is not proof the device is offline. The production host
        // has been measured answering in ~20s while perfectly healthy, so say
        // so rather than telling the user to check working Wi-Fi.
        sawTimeout = true;
        lastNetworkError = 'Request timed out.';
        lastNetworkDetails = error.toString();
        lastNetworkException = error;
      } on SocketException catch (error) {
        lastNetworkError = 'Unable to connect to backend.';
        lastNetworkDetails =
            'SocketException: ${error.message} (osError=${error.osError?.errorCode ?? 'n/a'})';
        lastNetworkException = error;
      } on HandshakeException catch (error) {
        lastNetworkError = 'Secure connection failed.';
        lastNetworkDetails = 'HandshakeException: $error';
        lastNetworkException = error;
      } on http.ClientException catch (error) {
        lastNetworkError = 'HTTP client connection failed.';
        lastNetworkDetails = 'ClientException: ${error.message}';
        lastNetworkException = error;
      } catch (error) {
        lastNetworkError = 'Unexpected network error.';
        lastNetworkDetails = '$error';
        lastNetworkException = error;
      }
    }

    // A 401/403 from a server we successfully reached is proof the network
    // worked, so a credential rejection outranks any network error seen along
    // the way. The previous guard required `lastNetworkError == null`, which
    // meant one flaky candidate URL could mask a genuine bad password and
    // report "No internet connection" instead.
    if (credentialRejection != null) {
      return _LoginPass(result: credentialRejection);
    }

    final baseUrls = AppConfig.authApiBaseUrlCandidates.join(', ');
    final networkReason = lastNetworkError ?? 'No reachable API login endpoint.';
    final devHint = AppConfig.useLocalTunnelBackends
        ? 'This build uses Cloudflare tunnel backends (USE_LOCAL_TUNNEL_BACKENDS=true). Ensure Cloudflared-hrmlocal is running and https://hrm.peoplesitsolution.online is healthy.'
        : 'Production builds target https://hrm.peoplesitsolution.com. For tunnel dev builds use --dart-define=USE_LOCAL_TUNNEL_BACKENDS=true.';
    debugPrint(
      'AuthService.login unreachable: $networkReason $devHint '
      'Tried bases: $baseUrls. Last URL: ${lastAttemptedLoginUrl ?? 'n/a'}. '
      'Details: ${lastNetworkDetails ?? 'n/a'}',
    );
    return _LoginPass(
      onlyTimeouts: sawTimeout && lastNetworkException is TimeoutException,
      result: AuthResult(
        success: false,
        message: switch (lastNetworkException) {
          HandshakeException() => UserFacingError.serverDown,
          // A timeout means the server was slow to answer, not that the device
          // is offline. Telling someone to check their Wi-Fi when the Wi-Fi is
          // fine sends them down the wrong path.
          TimeoutException() => UserFacingError.serverSlow,
          _ => UserFacingError.noInternet,
        },
      ),
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
          .timeout(_readTimeout);

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
            .timeout(_readTimeout);

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
              .timeout(_readTimeout);
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
          // Permissions are adopted here, at the single point where a profile
          // is parsed, rather than at each call site.
          //
          // It used to be called from AppBootstrap._warmAuthenticatedSession,
          // which covers auto-login only. LoginScreen fetches the profile from
          // its own hydration instead, so after a manual sign-in nothing ever
          // populated PermissionService: it stayed empty, failed closed, and
          // hid every gated module until the user closed and reopened the app.
          // Routing it through here fixes both paths, and any future one,
          // without each caller having to remember.
          PermissionService.instance.update(profile);
          return profile;
        }
      } on TimeoutException {
        // A slow connect is not a dead URL. Fall through to the next candidate
        // rather than treating it like a hard failure, so one congested
        // attempt does not blank the whole profile.
        continue;
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
    String? password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setBool(_rememberKey, rememberMe);
    if (rememberMe) {
      await prefs.setString(_emailKey, email);
      // Only a sign-in carries a password; a token refresh passes none, so the
      // remembered password is left untouched rather than cleared.
      if (password != null) {
        await prefs.setString(_passwordKey, password);
      }
    } else {
      await prefs.remove(_emailKey);
      await prefs.remove(_passwordKey);
    }
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

  Future<String?> getSavedPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_passwordKey);
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
    // Drop the previous user's grants before the next login can render a frame,
    // so a shared device never shows them the previous account's modules.
    PermissionService.instance.clear();
    try {
      await ZoneScopeService.instance.clear();
    } catch (_) {}

    try {
      await GeoTrackingService().pauseForLogout();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    // "Remember me" keeps the last email and password so the login screen can
    // prefill them — signing out ends the session, it does not forget the
    // login. Without it, nothing is kept.
    final rememberMe = prefs.getBool(_rememberKey) ?? false;
    if (!rememberMe) {
      await prefs.remove(_rememberKey);
      await prefs.remove(_emailKey);
      await prefs.remove(_passwordKey);
    }
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
    return _httpClient.get(
      Uri.parse(url),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
  }
}
