import 'dart:convert';
import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/auth_user_profile.dart';

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

  Future<AuthResult> login({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    String? lastNetworkError;

    for (final loginUrl in AppConfig.loginUrls) {
      try {
        final response = await http
            .post(
              Uri.parse(loginUrl),
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
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

          return AuthResult(
            success: true,
            message: data['message']?.toString() ?? 'Login successful',
            token: token,
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
      } on TimeoutException {
        lastNetworkError = 'Request timed out.';
      } catch (_) {
        lastNetworkError = 'Unable to connect to backend.';
      }
    }

    final baseUrls = AppConfig.apiBaseUrlCandidates.join(', ');
    final networkReason = lastNetworkError ?? 'No reachable API login endpoint.';
    return AuthResult(
      success: false,
      message:
          '$networkReason Verify backend URL/network. Default builds target https://hrm.peoplesitsolution.com. For local development, override with --dart-define=API_BASE_URL=http://192.168.x.x:8080. Tried bases: $baseUrls',
    );
  }

  Future<AuthUserProfile?> getCurrentUserProfile() async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      return null;
    }

    for (final url in AppConfig.currentUserUrls) {
      try {
        final response = await _authorizedGet(url: url, token: token)
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 404) {
          continue;
        }

        if (response.statusCode == 401) {
          await logout(invalidateServerSession: false);
          return null;
        }

        final data = _decodeMap(response.body);
        if (response.statusCode == 200 && data['user'] is Map<String, dynamic>) {
          return AuthUserProfile.fromJson(data['user'] as Map<String, dynamic>);
        }
      } catch (_) {
        continue;
      }
    }

    return null;
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
      for (final url in AppConfig.logoutUrls) {
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

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_rememberKey);
    await prefs.remove(_emailKey);
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
