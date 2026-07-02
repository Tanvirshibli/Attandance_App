import '../models/api_result.dart';
import '../models/payment_models.dart';
import 'hrm_api_client.dart';

class PaymentService {
  PaymentService({HrmApiClient? apiClient})
      : _apiClient = apiClient ?? HrmApiClient();

  final HrmApiClient _apiClient;

  Future<ApiResult<List<EmployeeLoan>>> getEmployeeLoans(int employeeId) async {
    final result = await _apiClient.getJson(
      '/api/v1/loans-employee',
      queryParameters: {'employeeId': '$employeeId'},
    );

    if (!result.success) {
      return ApiResult.fail(result.message ?? 'Could not load loans.');
    }

    final items = _extractList(result.data);
    return ApiResult.ok(items.map(EmployeeLoan.fromJson).toList());
  }

  Future<ApiResult<String>> postLoanPayment({
    required int employeeId,
    required int loanId,
    required double amount,
    required String date,
  }) async {
    final result = await _apiClient.postJson(
      '/api/v1/pay-loan/store',
      body: {
        'employeeId': employeeId,
        'loanId': loanId,
        'amount': amount,
        'date': date,
      },
    );

    if (!result.success) {
      return ApiResult.fail(result.message ?? 'Payment submission failed.');
    }

    return ApiResult.ok(
      result.data?['message']?.toString() ?? 'Payment submitted successfully.',
    );
  }

  Future<ApiResult<List<LoanPayment>>> getLoanPayments(int employeeId) async {
    final result = await _apiClient.getJson(
      '/api/v1/get/pay-loan',
      queryParameters: {'employeeId': '$employeeId'},
    );

    if (!result.success) {
      return ApiResult.fail(result.message ?? 'Could not load payments.');
    }

    final items = _extractList(result.data);
    return ApiResult.ok(items.map(LoanPayment.fromJson).toList());
  }

  Future<ApiResult<List<PayrollRecord>>> getPayrollRecords({
    required int employeeId,
    String? month,
  }) async {
    final params = <String, String>{'employeeId': '$employeeId'};
    if (month != null && month.isNotEmpty) {
      params['month'] = month;
    }

    final result = await _apiClient.getJson(
      '/api/v1/payroll',
      queryParameters: params,
    );

    if (!result.success) {
      return ApiResult.fail(result.message ?? 'Could not load payroll.');
    }

    final items = _extractList(result.data);
    return ApiResult.ok(items.map(PayrollRecord.fromJson).toList());
  }

  List<Map<String, dynamic>> _extractList(Map<String, dynamic>? data) {
    if (data == null) return [];
    final value = data['data'];
    if (value is List) {
      return value.whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }
}
