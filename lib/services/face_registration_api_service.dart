import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/face_registration_data.dart';
import 'auth_service.dart';
import 'device_identity_service.dart';

class FaceRegistrationApiService {
  FaceRegistrationApiService({AuthService? authService})
      : _authService = authService ?? AuthService();

  final AuthService _authService;
  final DeviceIdentityService _deviceIdentityService = DeviceIdentityService();

  Future<FaceRegistrationData?> fetchCurrentUserFaceRegistration() async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      return null;
    }

    for (final url in AppConfig.faceRegistrationUrls) {
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
          await _authService.logout(invalidateServerSession: false);
          return null;
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

  Future<bool> saveFaceRegistration(FaceRegistrationData registration) async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      return false;
    }

    final deviceMetadata = await _deviceIdentityService.getDeviceMetadata();
    final payload = {
      ...registration.toJson(),
      ...deviceMetadata,
    };

    for (final url in AppConfig.faceRegistrationUrls) {
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
          await _authService.logout(invalidateServerSession: false);
          return false;
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
