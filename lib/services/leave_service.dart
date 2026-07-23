import 'package:http/http.dart' as http;

import '../models/api_result.dart';
import '../models/leave_balance.dart';
import '../models/leave_record.dart';
import '../models/leave_type.dart';
import 'hrm_api_client.dart';

class LeaveService {
  LeaveService({HrmApiClient? apiClient}) : _apiClient = apiClient ?? HrmApiClient();

  final HrmApiClient _apiClient;

  Future<ApiResult<List<LeaveBalance>>> getBalances(int employeeId) async {
    final result = await _apiClient.getByKey(
      'leave.balance',
      fallbackPath: '/api/v1/new-leave-stocks',
      queryParameters: {'employeeId': '$employeeId', 'limit': '50'},
    );

    if (!result.success) {
      return ApiResult.fail(result.message ?? 'Could not load leave balance.');
    }

    final items = _extractList(result.data, keys: ['data', 'records']);
    var balances = items.map(LeaveBalance.fromJson).toList();
    balances = await _enrichBalanceTypeNames(balances);
    return ApiResult.ok(balances);
  }

  /// Fills missing leave type names from new-leave-types (by id), then
  /// legacy leavetypes (by id → lName, then code → lName).
  /// Stocks often store legacy leave_types.id as newLeaveTypeId.
  Future<List<LeaveBalance>> _enrichBalanceTypeNames(
    List<LeaveBalance> balances,
  ) async {
    if (balances.isEmpty) return balances;
    if (!balances.any((b) => b.hasGenericTypeName)) return balances;

    final byNewId = <int, ({String? name, String? code})>{};
    final newTypesResult = await _apiClient.getByKey(
      'leave.newTypes',
      fallbackPath: '/api/v1/new-leave-types',
      queryParameters: {'limit': '200'},
    );
    if (newTypesResult.success) {
      for (final row in _extractList(newTypesResult.data, keys: ['data'])) {
        final id = _parseInt(row['id']);
        if (id == null) continue;
        byNewId[id] = (
          name: _nonEmpty(
            row['leaveName'] ??
                row['leave_name'] ??
                row['name'] ??
                row['lName'],
          ),
          code: _nonEmpty(row['code']),
        );
      }
    }

    balances = balances.map((b) {
      if (!b.hasGenericTypeName || b.leaveTypeId == null) return b;
      final hit = byNewId[b.leaveTypeId];
      if (hit == null) return b;
      final name = hit.name ?? hit.code;
      return b.copyWith(
        leaveTypeName: name ?? b.leaveTypeName,
        code: b.code ?? hit.code,
      );
    }).toList();

    if (!balances.any((b) => b.hasGenericTypeName)) return balances;

    final byLegacyId = <int, String>{};
    final byCode = <String, String>{};
    final legacyResult = await getLeaveTypes();
    if (legacyResult.success && legacyResult.data != null) {
      for (final t in legacyResult.data!) {
        final name = t.name.trim();
        if (name.isEmpty) continue;
        if (t.id > 0) {
          byLegacyId[t.id] = name;
        }
        final code = t.code?.trim().toLowerCase();
        if (code != null && code.isNotEmpty) {
          byCode[code] = name;
        }
      }
    }

    return balances.map((b) {
      if (!b.hasGenericTypeName) return b;

      if (b.leaveTypeId != null && byLegacyId.containsKey(b.leaveTypeId)) {
        return b.copyWith(leaveTypeName: byLegacyId[b.leaveTypeId]);
      }

      final codeKey = b.code?.trim().toLowerCase();
      if (codeKey != null &&
          codeKey.isNotEmpty &&
          byCode.containsKey(codeKey)) {
        return b.copyWith(leaveTypeName: byCode[codeKey]);
      }

      if (b.leaveTypeId != null) {
        return b.copyWith(leaveTypeName: 'Leave type #${b.leaveTypeId}');
      }
      // Avoid labeling with stock row id when type id is unknown.
      return b;
    }).toList();
  }

  Future<ApiResult<List<LeaveRecord>>> getLeaveHistory({
    required int employeeId,
    String? status,
  }) async {
    final params = <String, String>{
      'employeeId': '$employeeId',
    };
    if (status != null && status.isNotEmpty && status.toLowerCase() != 'all') {
      params['status'] = status.toLowerCase();
    }

    final result = await _apiClient.getByKey(
      'leave.history',
      fallbackPath: '/api/v1/leaves',
      queryParameters: params,
    );
    if (!result.success) {
      return ApiResult.fail(result.message ?? 'Could not load leave history.');
    }

    final items = _extractList(result.data, keys: ['data']);
    return ApiResult.ok(items.map(LeaveRecord.fromJson).toList());
  }

  Future<ApiResult<List<LeaveType>>> getLeaveTypes() async {
    final result = await _apiClient.getByKey(
      'leave.types',
      fallbackPath: '/api/v1/leavetypes',
    );
    if (!result.success) {
      return ApiResult.fail(result.message ?? 'Could not load leave types.');
    }

    final items = _extractList(result.data, keys: ['data']);
    return ApiResult.ok(items.map(LeaveType.fromJson).toList());
  }

  Future<ApiResult<String>> applyLeave({
    required int employeeId,
    required int leaveTypeId,
    required String startDate,
    required String endDate,
    required String reason,
    String? documentPath,
  }) async {
    final fields = <String, String>{
      'employeeId': '$employeeId',
      'leaveTypeId': '$leaveTypeId',
      'startDate': startDate,
      'endDate': endDate,
      'reason': reason,
    };

    final files = <http.MultipartFile>[];
    if (documentPath != null && documentPath.isNotEmpty) {
      files.add(await http.MultipartFile.fromPath('document', documentPath));
    }

    final result = await _apiClient.postMultipart(
      '/api/v1/leaves',
      fields: fields,
      files: files,
    );

    if (!result.success) {
      return ApiResult.fail(result.message ?? 'Could not submit leave request.');
    }

    return ApiResult.ok(
      result.data?['message']?.toString() ?? 'Leave submitted successfully.',
    );
  }

  Future<ApiResult<List<Map<String, dynamic>>>> getHolidays({
    String? from,
    String? to,
  }) async {
    final params = <String, String>{};
    if (from != null && to != null) {
      params['from'] = from;
      params['to'] = to;
    }

    final result = await _apiClient.getByKey(
      'leave.holidays',
      fallbackPath: '/api/v1/mobile/holidays',
      queryParameters: params.isEmpty ? null : params,
    );

    if (!result.success) {
      return ApiResult.fail(result.message ?? 'Could not load holidays.');
    }

    final items = _extractList(result.data, keys: ['data']);
    return ApiResult.ok(items);
  }

  List<Map<String, dynamic>> _extractList(
    Map<String, dynamic>? data, {
    required List<String> keys,
  }) {
    if (data == null) return [];

    for (final key in keys) {
      final value = data[key];
      if (value is List) {
        return value.whereType<Map<String, dynamic>>().toList();
      }
    }

    if (data['data'] is List) {
      return (data['data'] as List).whereType<Map<String, dynamic>>().toList();
    }

    return [];
  }

  static int? _parseInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }

  static String? _nonEmpty(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }
}
