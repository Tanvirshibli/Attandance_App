import '../services/hrm_api_client.dart';
import '../models/api_result.dart';
import '../models/attendance_summary.dart';

class AttendanceReportService {
  AttendanceReportService({HrmApiClient? apiClient})
      : _apiClient = apiClient ?? HrmApiClient();

  final HrmApiClient _apiClient;

  Future<ApiResult<AttendanceSummary>> getSummary({
    required int employeeId,
    required DateTime from,
    required DateTime to,
  }) async {
    final fromStr = _dateStr(from);
    final toStr = _dateStr(to);

    final result = await _apiClient.getJson(
      '/api/v1/single-employee-attendance-details',
      queryParameters: {
        'employee_id': '$employeeId',
        'start_date': fromStr,
        'end_date': toStr,
      },
    );

    if (!result.success || result.data == null) {
      return ApiResult.fail(result.message ?? 'Could not load summary.');
    }

    return ApiResult.ok(AttendanceSummary.fromJson(result.data!));
  }

  String _dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
