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
    final result = await _apiClient.getJson(
      '/api/v1/new-leave-stocks',
      queryParameters: {'employeeId': '$employeeId', 'limit': '50'},
    );

    if (!result.success) {
      return ApiResult.fail(result.message ?? 'Could not load leave balance.');
    }

    final items = _extractList(result.data, keys: ['data', 'records']);
    return ApiResult.ok(
      items.map(LeaveBalance.fromJson).toList(),
    );
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

    final result = await _apiClient.getJson('/api/v1/leaves', queryParameters: params);
    if (!result.success) {
      return ApiResult.fail(result.message ?? 'Could not load leave history.');
    }

    final items = _extractList(result.data, keys: ['data']);
    return ApiResult.ok(items.map(LeaveRecord.fromJson).toList());
  }

  Future<ApiResult<List<LeaveType>>> getLeaveTypes() async {
    final result = await _apiClient.getJson('/api/v1/leavetypes');
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

    // Paginated resource collection at root
    if (data['data'] is List) {
      return (data['data'] as List).whereType<Map<String, dynamic>>().toList();
    }

    return [];
  }
}
