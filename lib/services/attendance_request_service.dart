import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/attendance_request_record.dart';
import '../models/face_registration_data.dart';
import 'auth_service.dart';
import 'device_identity_service.dart';

class AttendanceSubmitResult {
  const AttendanceSubmitResult({
    required this.success,
    this.message,
  });

  final bool success;
  final String? message;
}

class AttendanceRequestService {
  AttendanceRequestService({AuthService? authService})
      : _authService = authService ?? AuthService();

  final AuthService _authService;
  final DeviceIdentityService _deviceIdentityService = DeviceIdentityService();

  Future<List<AttendanceRequestRecord>> getAttendanceRecords({
    String? status,
    int limit = 100,
  }) async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      return const [];
    }

    for (final url in AppConfig.attendanceRequestUrls) {
      try {
        final queryParameters = <String, String>{
          'limit': '$limit',
        };
        if (status != null && status.trim().isNotEmpty) {
          queryParameters['status'] = status.trim();
        }

        final response = await http
            .get(
              Uri.parse(url).replace(queryParameters: queryParameters),
              headers: {
                'Accept': 'application/json',
                'Authorization': 'Bearer $token',
              },
            )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 404) {
          continue;
        }

        if (response.statusCode == 401) {
          await _authService.logout(invalidateServerSession: false);
          return const [];
        }

        if (response.statusCode != 200) {
          continue;
        }

        final data = _decodeMap(response.body);
        final recordsRaw = data['records'];
        if (recordsRaw is! List) {
          return const [];
        }

        return recordsRaw
            .whereType<Map<String, dynamic>>()
            .map(AttendanceRequestRecord.fromJson)
            .toList();
      } catch (_) {
        continue;
      }
    }

    return const [];
  }

  Future<List<AttendanceRequestRecord>> getRequestedRecords() {
    return getAttendanceRecords(status: 'requested');
  }

  Future<AttendanceSubmitResult> submitSelfPunch({
    required bool isCheckOut,
    required double latitude,
    required double longitude,
    required String address,
    required FaceRegistrationData? faceRegistration,
  }) async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      return const AttendanceSubmitResult(
        success: false,
        message: 'Authentication token missing. Please login again.',
      );
    }

    final deviceMetadata = await _deviceIdentityService.getDeviceMetadata();
    final now = DateTime.now().toIso8601String();
    final body = <String, dynamic>{
      'direction': isCheckOut ? 'out' : 'in',
      if (!isCheckOut) 'requestedInTime': now,
      if (isCheckOut) 'requestedOutTime': now,
      'lat': latitude,
      'lng': longitude,
      'address': address,
      'requestType': 'self_punch',
      ...deviceMetadata,
      if (faceRegistration != null)
        'face_registration': {
          ...faceRegistration.toJson(),
          ...deviceMetadata,
        },
    };

    String? networkError;

    for (final url in AppConfig.attendanceRequestUrls) {
      try {
        final response = await http
            .post(
              Uri.parse(url),
              headers: {
                'Accept': 'application/json',
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 20));

        if (response.statusCode == 404) {
          continue;
        }

        final data = _decodeMap(response.body);
        if (response.statusCode == 201 || response.statusCode == 200) {
          return AttendanceSubmitResult(
            success: true,
            message: data['message']?.toString() ??
                'Attendance request submitted successfully.',
          );
        }

        if (response.statusCode == 401) {
          await _authService.logout(invalidateServerSession: false);
          return const AttendanceSubmitResult(
            success: false,
            message: 'Session expired. Please login again.',
          );
        }

        return AttendanceSubmitResult(
          success: false,
          message: data['message']?.toString() ??
              'Attendance request failed (${response.statusCode}).',
        );
      } on TimeoutException {
        networkError = 'Request timed out.';
      } catch (_) {
        networkError = 'Unable to connect to backend.';
      }
    }

    return AttendanceSubmitResult(
      success: false,
      message: networkError ?? 'No reachable attendance endpoint.',
    );
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
