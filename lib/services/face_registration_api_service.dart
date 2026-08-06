import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/face_registration_data.dart';
import 'auth_service.dart';
import 'device_identity_service.dart';
import 'endpoint_config_service.dart';

class FaceRegistrationApiService {
  FaceRegistrationApiService({AuthService? authService})
      : _authService = authService ?? AuthService();

  final AuthService _authService;
  final DeviceIdentityService _deviceIdentityService = DeviceIdentityService();
  final EndpointConfigService _configService = EndpointConfigService.instance;

  Future<FaceRegistrationData?> fetchCurrentUserFaceRegistration() async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      return null;
    }

    for (final url in await _faceRegistrationUrls()) {
      try {
        final response = await http.get(
          Uri.parse(url),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 404) {
          continue;
        }

        if (response.statusCode == 401) {
          final refreshed = await _authService.refreshToken();
          if (!refreshed) {
            await _authService.logout(invalidateServerSession: false);
            return null;
          }
          final refreshedToken = await _authService.getToken();
          if (refreshedToken == null || refreshedToken.isEmpty) {
            return null;
          }
          final retry = await http.get(
            Uri.parse(url),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $refreshedToken',
            },
          ).timeout(const Duration(seconds: 15));
          if (retry.statusCode == 401) {
            await _authService.logout(invalidateServerSession: false);
            return null;
          }
          if (retry.statusCode != 200) {
            continue;
          }
          final retryBody = _decodeMap(retry.body);
          return FaceRegistrationData.fromJson(retryBody['face_registration']);
        }

        if (response.statusCode != 200) {
          continue;
        }

        final body = _decodeMap(response.body);
        return FaceRegistrationData.fromJson(body['face_registration']);
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  Future<bool> saveFaceRegistration(
    FaceRegistrationData registration, {
    int? canonicalEmployeeId,
  }) async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      return false;
    }

    final deviceMetadata = await _deviceIdentityService.getDeviceMetadata();
    final payload = {
      ...registration.toJson(),
      ...deviceMetadata,
      if (canonicalEmployeeId != null && canonicalEmployeeId > 0)
        'zktecoPin': '$canonicalEmployeeId',
    };

    for (final url in await _faceRegistrationUrls()) {
      try {
        final response = await http
            .post(
              Uri.parse(url),
              headers: {
                'Accept': 'application/json',
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 20));

        if (response.statusCode == 404) {
          continue;
        }

        if (response.statusCode == 401) {
          final refreshed = await _authService.refreshToken();
          if (!refreshed) {
            await _authService.logout(invalidateServerSession: false);
            return false;
          }
          final refreshedToken = await _authService.getToken();
          if (refreshedToken == null || refreshedToken.isEmpty) {
            return false;
          }
          final retry = await http
              .post(
                Uri.parse(url),
                headers: {
                  'Accept': 'application/json',
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $refreshedToken',
                },
                body: jsonEncode(payload),
              )
              .timeout(const Duration(seconds: 20));
          if (retry.statusCode == 401) {
            await _authService.logout(invalidateServerSession: false);
            return false;
          }
          if (retry.statusCode == 200 || retry.statusCode == 201) {
            return true;
          }
          continue;
        }

        if (response.statusCode == 200 || response.statusCode == 201) {
          return true;
        }
      } catch (_) {
        continue;
      }
    }

    return false;
  }

  Future<List<String>> _faceRegistrationUrls() async {
    final getUrl = await _configService.resolveUrl('face.registration.get');
    final postUrl = await _configService.resolveUrl('face.registration');
    final urls = <String>{};
    if (getUrl != null) urls.add(getUrl);
    if (postUrl != null) urls.add(postUrl);
    urls.addAll(AppConfig.faceRegistrationUrls);
    return urls.toList();
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
