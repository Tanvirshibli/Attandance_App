import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/attendance_request_record.dart';
import 'auth_service.dart';
import 'device_identity_service.dart';
import 'endpoint_config_service.dart';

class AttendanceSubmitResult {
  const AttendanceSubmitResult({
    required this.success,
    this.message,
    this.record,
  });

  final bool success;
  final String? message;
  final AttendanceRequestRecord? record;
}

class AttendanceRequestService {
  AttendanceRequestService({AuthService? authService})
      : _authService = authService ?? AuthService();

  final AuthService _authService;
  final DeviceIdentityService _deviceIdentityService = DeviceIdentityService();
  final EndpointConfigService _configService = EndpointConfigService.instance;

  /// Loads attendance for Home / History / Report.
  ///
  /// ZKTeco BFF is primary (same DB as the web Attendance Requests grid).
  /// HRM JWT rows are merged in so android-only ERP punches are not lost.
  /// Same calendar day collapses to one display row (earliest in, latest out).
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

    final futures = <Future<List<AttendanceRequestRecord>>>[];

    if (employeeId != null && employeeId > 0) {
      futures.add(
        _fetchFromZktecoEndpoint(
          employeeId: employeeId,
          status: status,
          from: from,
          to: to,
          limit: limit,
        ),
      );
    }

    if (token != null && token.isNotEmpty) {
      futures.add(
        () async {
          final jwt = await _fetchFromJwtEndpoint(
            token: token,
            status: status,
            from: from,
            to: to,
            limit: limit,
          );
          return jwt ?? const <AttendanceRequestRecord>[];
        }(),
      );
    }

    if (futures.isEmpty) {
      return const [];
    }

    final batches = await Future.wait(futures);
    final merged = _mergeByCalendarDay([
      for (final batch in batches) ...batch,
    ]);

    if (merged.length > limit) {
      return merged.take(limit).toList();
    }
    return merged;
  }

  Future<List<AttendanceRequestRecord>> _fetchFromZktecoEndpoint({
    required int employeeId,
    String? status,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async {
    final merged = <AttendanceRequestRecord>[];

    for (final url in await _attendanceListUrls()) {
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
        } else if (from != null) {
          queryParameters['attDate'] = _dateStr(from);
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
        final recordsRaw = _extractRecordsList(data);
        if (recordsRaw.isEmpty) {
          continue;
        }

        merged.addAll(
          recordsRaw.map(AttendanceRequestRecord.fromJson),
        );
      } catch (_) {
        continue;
      }
    }

    return merged;
  }

  Future<List<AttendanceRequestRecord>?> _fetchFromJwtEndpoint({
    required String token,
    String? status,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async {
    final merged = <AttendanceRequestRecord>[];
    var anyReachable = false;

    for (final url in await _jwtAttendanceUrls()) {
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

        anyReachable = true;
        final data = _decodeMap(response.body);
        final recordsRaw = _extractRecordsList(data);
        if (recordsRaw.isEmpty) continue;

        merged.addAll(
          recordsRaw.map(AttendanceRequestRecord.fromJson),
        );
      } catch (_) {
        continue;
      }
    }

    if (!anyReachable && merged.isEmpty) return null;
    return merged;
  }

  /// Merged attendance for Home: today-scoped fetch plus recent history.
  Future<List<AttendanceRequestRecord>> getHomeAttendanceRecords({
    required int? employeeId,
  }) async {
    if (!await _hasLocalSession()) {
      return const [];
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final results = await Future.wait([
      getAttendanceRecords(employeeId: employeeId, from: today, to: today),
      getAttendanceRecords(employeeId: employeeId),
    ]);

    return _mergeByCalendarDay([
      for (final batch in results) ...batch,
    ]);
  }

  /// Collapse same-day rows (earliest in, latest out).
  AttendanceRequestRecord mergeRecords(List<AttendanceRequestRecord> group) {
    if (group.isEmpty) {
      throw ArgumentError.value(group, 'group', 'must not be empty');
    }
    if (group.length == 1) return group.first;
    return _mergeDayGroup(group);
  }

  /// Best today row: all records matching [today] merged into one span.
  AttendanceRequestRecord? resolveTodayRecord(
    List<AttendanceRequestRecord> records,
    DateTime today,
  ) {
    final todayRows =
        records.where((record) => record.matchesCalendarDay(today)).toList();
    if (todayRows.isEmpty) return null;
    if (todayRows.length == 1) return todayRows.first;
    return mergeRecords(todayRows);
  }

  /// One display row per calendar day: earliest in, latest out, prefer non-rejected.
  List<AttendanceRequestRecord> _mergeByCalendarDay(
    List<AttendanceRequestRecord> records,
  ) {
    if (records.isEmpty) return const [];

    final byDay = <String, List<AttendanceRequestRecord>>{};
    for (final record in records) {
      final day = record.effectiveCalendarDay;
      final key = day == null
          ? 'raw:${record.attDate}|${record.id}'
          : '${day.year.toString().padLeft(4, '0')}-'
              '${day.month.toString().padLeft(2, '0')}-'
              '${day.day.toString().padLeft(2, '0')}';
      byDay.putIfAbsent(key, () => <AttendanceRequestRecord>[]).add(record);
    }

    final merged = <AttendanceRequestRecord>[];
    for (final entry in byDay.entries) {
      final group = entry.value;
      if (group.length == 1) {
        merged.add(group.first);
        continue;
      }
      merged.add(_mergeDayGroup(group));
    }

    merged.sort((a, b) {
      final aDay = a.effectiveCalendarDay;
      final bDay = b.effectiveCalendarDay;
      if (aDay != null && bDay != null) {
        final cmp = bDay.compareTo(aDay);
        if (cmp != 0) return cmp;
      }
      return b.id.compareTo(a.id);
    });

    return merged;
  }

  AttendanceRequestRecord _mergeDayGroup(List<AttendanceRequestRecord> group) {
    DateTime? earliestIn;
    String? earliestInRaw;
    DateTime? latestOut;
    String? latestOutRaw;
    var anyRejected = true;
    var maxId = 0;
    String attDate = group.first.attDate;
    String requestType = group.first.requestType;
    String? workflowStage;
    String? supervisorStatus;
    String? hrStatus;
    String? address;
    double? latitude;
    double? longitude;
    bool? faceVerified;
    String? createdAt;
    final deviceTypes = <String>{};

    for (final r in group) {
      if (r.id > maxId) maxId = r.id;
      if (r.attDate.isNotEmpty) attDate = r.attDate;
      if (!r.isRejected) anyRejected = false;

      final dt = (r.deviceType ?? '').trim().toLowerCase();
      if (dt.isNotEmpty) deviceTypes.add(dt);

      final inParsed =
          AttendanceRequestRecord.parseFlexibleDateTime(r.requestedInTime);
      if (inParsed != null &&
          (earliestIn == null || inParsed.isBefore(earliestIn))) {
        earliestIn = inParsed;
        earliestInRaw = r.requestedInTime;
      }

      final outParsed =
          AttendanceRequestRecord.parseFlexibleDateTime(r.requestedOutTime);
      if (outParsed != null &&
          (latestOut == null || outParsed.isAfter(latestOut))) {
        latestOut = outParsed;
        latestOutRaw = r.requestedOutTime;
      }

      workflowStage ??= r.workflowStage;
      supervisorStatus ??= r.supervisorStatus;
      hrStatus ??= r.hrStatus;
      address ??= r.address;
      latitude ??= r.latitude;
      longitude ??= r.longitude;
      faceVerified ??= r.faceVerified;
      createdAt ??= r.createdAt;

      if (r.requestType == 'zkteco_daily_span' ||
          (r.deviceType ?? '').toLowerCase() == 'zkteco') {
        requestType = r.requestType;
      }
    }

    String? deviceType;
    if (deviceTypes.length > 1) {
      deviceType = 'mixed';
    } else if (deviceTypes.isNotEmpty) {
      deviceType = deviceTypes.first;
    }

    // Best status wins: approved > requested > rejected.
    String status = 'rejected';
    var bestRank = -1;
    for (final r in group) {
      final rank = _statusRank(r.status);
      if (rank > bestRank) {
        bestRank = rank;
        status = r.status;
      }
    }
    if (anyRejected && group.every((r) => r.isRejected)) {
      status = 'rejected';
    }

    return AttendanceRequestRecord(
      id: maxId,
      attDate: attDate,
      requestType: requestType,
      status: status,
      requestedInTime: earliestInRaw,
      requestedOutTime: latestOutRaw,
      deviceType: deviceType,
      workflowStage: workflowStage,
      supervisorStatus: supervisorStatus,
      hrStatus: hrStatus,
      address: address,
      latitude: latitude,
      longitude: longitude,
      faceVerified: faceVerified,
      createdAt: createdAt,
    );
  }

  int _statusRank(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return 2;
      case 'requested':
      case 'pending':
        return 1;
      default:
        return 0;
    }
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
    bool faceVerified = false,
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
    final token = await _authService.getToken();
    final nowDt = DateTime.now();
    final now = nowDt.toIso8601String();
    final body = <String, dynamic>{
      'employee_id': employeeId,
      'direction': isCheckOut ? 'out' : 'in',
      'attDate': _dateStr(nowDt),
      if (!isCheckOut) 'requestedInTime': now,
      if (isCheckOut) 'requestedOutTime': now,
      'lat': latitude,
      'lng': longitude,
      'address': address,
      'face_verified': faceVerified,
      'requestType': 'self_punch',
      ...deviceMetadata,
    };

    String? networkError;

    for (final url in await _attendancePunchUrls()) {
      try {
        final headers = <String, String>{
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'User-Agent': 'PPHLAttendance/2.2 (Android; Flutter)',
        };
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }

        final response = await http
            .post(
              Uri.parse(url),
              headers: headers,
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
            record: _parsePunchRecord(
              data,
              postBody: body,
              isCheckOut: isCheckOut,
            ),
          );
        }

        final serverMessage = _extractErrorMessage(data) ??
            'Attendance request failed (${response.statusCode}).';
        return AttendanceSubmitResult(
          success: false,
          message: serverMessage,
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

  Future<List<String>> _attendanceListUrls() async {
    final dynamicUrl = await _configService.resolveUrl('attendance.list');
    if (dynamicUrl != null && dynamicUrl.isNotEmpty) {
      return [dynamicUrl, ...AppConfig.attendanceRequestUrls];
    }
    return AppConfig.attendanceRequestUrls;
  }

  Future<List<String>> _attendancePunchUrls() async {
    final dynamicUrl = await _configService.resolveUrl('attendance.punch');
    if (dynamicUrl != null && dynamicUrl.isNotEmpty) {
      return [dynamicUrl, ...AppConfig.attendanceRequestUrls];
    }
    return AppConfig.attendanceRequestUrls;
  }

  /// HRM JWT attendance URLs only — never ZKTeco `attendance.list`.
  Future<List<String>> _jwtAttendanceUrls() async {
    final urls = <String>[];
    final hrmUrl = await _configService.resolveUrl('auth.profile');
    if (hrmUrl != null && hrmUrl.isNotEmpty) {
      final hrmBase = hrmUrl.replaceAll('/api/v1/get-my-info', '');
      urls.add('$hrmBase/api/v1/mobile/attendance-requests');
    }
    for (final fallback in AppConfig.mobileAttendanceJwtUrls) {
      if (!urls.contains(fallback)) {
        urls.add(fallback);
      }
    }
    return urls;
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

  String? _extractErrorMessage(Map<String, dynamic> data) {
    final error = data['error']?.toString().trim();
    if (error != null && error.isNotEmpty) return error;
    final message = data['message']?.toString().trim();
    if (message != null && message.isNotEmpty) return message;
    return null;
  }

  List<Map<String, dynamic>> _extractRecordsList(Map<String, dynamic> data) {
    final recordsRaw = data['records'];
    if (recordsRaw is List) {
      return recordsRaw.whereType<Map<String, dynamic>>().toList();
    }

    final dataRaw = data['data'];
    if (dataRaw is List) {
      return dataRaw.whereType<Map<String, dynamic>>().toList();
    }

    if (dataRaw is Map<String, dynamic>) {
      final nested = dataRaw['records'];
      if (nested is List) {
        return nested.whereType<Map<String, dynamic>>().toList();
      }
    }

    return const [];
  }

  AttendanceRequestRecord? _parsePunchRecord(
    Map<String, dynamic> data, {
    required Map<String, dynamic> postBody,
    required bool isCheckOut,
  }) {
    final request = data['request'];
    if (request is Map<String, dynamic>) {
      return AttendanceRequestRecord.fromJson(request);
    }
    return synthesizePunchRecord(
      postBody: postBody,
      isCheckOut: isCheckOut,
    );
  }

  /// Builds a local today row when POST succeeds but omits the request wrapper.
  AttendanceRequestRecord synthesizePunchRecord({
    required Map<String, dynamic> postBody,
    required bool isCheckOut,
  }) {
    final nowDt = DateTime.now();
    final attDate = postBody['attDate']?.toString() ?? _dateStr(nowDt);
    final inRaw = postBody['requestedInTime']?.toString();
    final outRaw = postBody['requestedOutTime']?.toString();

    return AttendanceRequestRecord(
      id: 0,
      attDate: attDate,
      requestType: postBody['requestType']?.toString() ?? 'self_punch',
      status: 'requested',
      requestedInTime: isCheckOut ? null : (inRaw ?? nowDt.toIso8601String()),
      requestedOutTime: isCheckOut ? (outRaw ?? nowDt.toIso8601String()) : null,
      deviceType: 'android',
    );
  }
}
