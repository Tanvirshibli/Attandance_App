import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/attendance_request_record.dart';
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
    required int? employeeId,
    String? status,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async {
    if (!await _hasLocalSession()) {
      return const [];
    }

    final token = await _authService.getToken();

    // Prefer HRM JWT endpoint (auto-scoped to logged-in employee).
    if (token != null && token.isNotEmpty) {
      final jwtRecords = await _fetchFromJwtEndpoint(
        token: token,
        status: status,
        from: from,
        to: to,
        limit: limit,
      );
      if (jwtRecords != null) {
        return jwtRecords;
      }
    }

    if (employeeId == null || employeeId <= 0) {
      return const [];
    }

    for (final url in AppConfig.attendanceRequestUrls) {
      try {
        final queryParameters = <String, String>{
          'employee_id': '$employeeId',
          'limit': '$limit',
        };
        if (status != null && status.trim().isNotEmpty) {
          queryParameters['status'] = status.trim();
        }
        if (from != null && to != null) {
          queryParameters['from'] = _dateStr(from);
          queryParameters['to'] = _dateStr(to);
        }

        final response = await http
            .get(
              Uri.parse(url).replace(queryParameters: queryParameters),
              headers: {
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 404) {
          continue;
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

  Future<List<AttendanceRequestRecord>?> _fetchFromJwtEndpoint({
    required String token,
    String? status,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async {
    for (final url in AppConfig.mobileAttendanceJwtUrls) {
      try {
        final queryParameters = <String, String>{
          'limit': '$limit',
        };
        if (status != null && status.trim().isNotEmpty) {
          final normalized = status.trim().toLowerCase();
          queryParameters['status'] =
              normalized == 'requested' ? 'requested' : normalized;
        }
        if (from != null && to != null) {
          queryParameters['from'] = _dateStr(from);
          queryParameters['to'] = _dateStr(to);
        }

        final response = await http
            .get(
              Uri.parse(url).replace(queryParameters: queryParameters),
              headers: {
                'Accept': 'application/json',
                'Authorization': 'Bearer $token',
                'User-Agent': 'PPHLAttendance/2.0 (Android; Flutter)',
              },
            )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 404) continue;
        if (response.statusCode != 200) continue;

        final data = _decodeMap(response.body);
        final recordsRaw = data['records'];
        if (recordsRaw is! List) return const [];

        return recordsRaw
            .whereType<Map<String, dynamic>>()
            .map(AttendanceRequestRecord.fromJson)
            .toList();
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  String _dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<List<AttendanceRequestRecord>> getRequestedRecords({
    required int? employeeId,
  }) {
    return getAttendanceRecords(employeeId: employeeId, status: 'requested');
  }

  Future<AttendanceSubmitResult> submitSelfPunch({
    required int? employeeId,
    required bool isCheckOut,
    required double latitude,
    required double longitude,
    required String address,
  }) async {
    if (!await _hasLocalSession()) {
      return const AttendanceSubmitResult(
        success: false,
        message: 'Authentication token missing. Please login again.',
      );
    }

    if (employeeId == null || employeeId <= 0) {
      return const AttendanceSubmitResult(
        success: false,
        message: 'Employee profile is not linked. Please contact HR.',
      );
    }

    final deviceMetadata = await _deviceIdentityService.getDeviceMetadata();
    final now = DateTime.now().toIso8601String();
    final body = <String, dynamic>{
      'employee_id': employeeId,
      'direction': isCheckOut ? 'out' : 'in',
      if (!isCheckOut) 'requestedInTime': now,
      if (isCheckOut) 'requestedOutTime': now,
      'lat': latitude,
      'lng': longitude,
      'address': address,
      'requestType': 'self_punch',
      ...deviceMetadata,
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

  Future<bool> _hasLocalSession() async {
    final token = await _authService.getToken();
    return token != null && token.isNotEmpty;
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
