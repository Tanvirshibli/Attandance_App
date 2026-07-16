import '../config/app_config.dart';
import '../data/payments_demo_data.dart';
import '../models/api_result.dart';
import '../models/payment_models.dart';
import 'endpoint_config_service.dart';
import 'hrm_api_client.dart';

class PaymentService {
  PaymentService({
    HrmApiClient? apiClient,
    EndpointConfigService? configService,
  })  : _apiClient = apiClient ?? HrmApiClient(),
        _configService = configService ?? EndpointConfigService.instance;

  final HrmApiClient _apiClient;
  final EndpointConfigService _configService;

  bool get useDemoData => AppConfig.usePaymentDemoData;

  Future<bool> isPaymentEnabled() =>
      _configService.isFeatureEnabled('payment.enabled', defaultValue: false);

  Future<ApiResult<PaymentsHubSummary>> getHubSummary(int employeeId) async {
    if (useDemoData) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      return ApiResult.ok(PaymentsDemoData.summary());
    }

    final payslips = await getPayrollRecords(employeeId: employeeId);
    final loans = await getEmployeeLoans(employeeId);
    final pf = await getProvidentFund(employeeId);

    final slips = payslips.data ?? const <PayrollRecord>[];
    final openLoans = loans.data ?? const <EmployeeLoan>[];
    final remaining = openLoans.fold<double>(
      0,
      (sum, loan) => sum + (loan.remainingAmount ?? 0),
    );

    return ApiResult.ok(
      PaymentsHubSummary(
        latestNetPay: slips.isEmpty
            ? null
            : (slips.first.netReceivable ?? slips.first.netPay),
        latestPayslipMonth: slips.isEmpty ? null : slips.first.month,
        openLoanRemaining: remaining,
        pfClosingBalance: pf.data?.closingBalanceWithProfit ??
            pf.data?.closingBalance,
      ),
    );
  }

  Future<ApiResult<List<EmployeeLoan>>> getEmployeeLoans(int employeeId) async {
    if (useDemoData) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return ApiResult.ok(PaymentsDemoData.loans());
    }

    final result = await _apiClient.getByKey(
      'payment.loans',
      fallbackPath: '/api/v1/loans-employee',
      queryParameters: {'employeeId': '$employeeId'},
    );

    if (!result.success) {
      return ApiResult.fail(result.message ?? 'Could not load loans.');
    }

    final items = _extractList(result.data);
    return ApiResult.ok(items.map(EmployeeLoan.fromJson).toList());
  }

  Future<ApiResult<EmployeeLoan>> getLoanDetail(int loanId) async {
    if (useDemoData) {
      final match = PaymentsDemoData.loans().where((l) => l.id == loanId);
      if (match.isEmpty) {
        return ApiResult.fail('Loan not found.');
      }
      return ApiResult.ok(match.first);
    }

    final hrmBase = await _configService.hrmBaseUrl();
    final result = await _apiClient.getJson(
      '/api/v1/loan/$loanId',
      baseUrl: hrmBase,
    );

    if (!result.success) {
      return ApiResult.fail(result.message ?? 'Could not load loan.');
    }

    final raw = result.data?['data'] ?? result.data;
    if (raw is Map<String, dynamic>) {
      return ApiResult.ok(EmployeeLoan.fromJson(raw));
    }
    return ApiResult.fail('Invalid loan response.');
  }

  Future<ApiResult<String>> postLoanPayment({
    required int employeeId,
    required int loanId,
    required double amount,
    required String date,
    String? paymentMethod,
  }) async {
    if (useDemoData) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      return ApiResult.ok('Demo payment submitted successfully.');
    }

    final result = await _apiClient.postByKey(
      'payment.post',
      fallbackPath: '/api/v1/pay-loan/store',
      body: {
        'employeeId': employeeId,
        'loanId': loanId,
        'amount': amount,
        'date': date,
        if (paymentMethod != null) 'paymentMethod': paymentMethod,
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
    if (useDemoData) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return ApiResult.ok(PaymentsDemoData.loanPayments());
    }

    final result = await _apiClient.getByKey(
      'payment.history',
      fallbackPath: '/api/v1/get/pay-loan',
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
    if (useDemoData) {
      await Future<void>.delayed(const Duration(milliseconds: 220));
      return ApiResult.ok(PaymentsDemoData.payslips());
    }

    final params = <String, String>{'employeeId': '$employeeId'};
    if (month != null && month.isNotEmpty) {
      params['month'] = month;
    }

    final result = await _apiClient.getByKey(
      'payment.payroll',
      fallbackPath: '/api/v1/payroll',
      queryParameters: params,
    );

    if (!result.success) {
      return ApiResult.fail(result.message ?? 'Could not load payroll.');
    }

    final items = _extractList(result.data);
    return ApiResult.ok(items.map(PayrollRecord.fromJson).toList());
  }

  Future<ApiResult<PayrollRecord>> getPayslipDetail(int payrollId) async {
    if (useDemoData) {
      final match = PaymentsDemoData.payslips().where((p) => p.id == payrollId);
      if (match.isEmpty) {
        return ApiResult.fail('Payslip not found.');
      }
      return ApiResult.ok(match.first);
    }

    final hrmBase = await _configService.hrmBaseUrl();
    final result = await _apiClient.getJson(
      '/api/v1/payroll/$payrollId',
      baseUrl: hrmBase,
    );

    if (!result.success) {
      return ApiResult.fail(result.message ?? 'Could not load payslip.');
    }

    final raw = result.data?['data'] ?? result.data;
    if (raw is Map<String, dynamic>) {
      return ApiResult.ok(PayrollRecord.fromJson(raw));
    }
    return ApiResult.fail('Invalid payslip response.');
  }

  Future<ApiResult<ProvidentFundRecord>> getProvidentFund(int employeeId) async {
    if (useDemoData) {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      return ApiResult.ok(PaymentsDemoData.providentFund());
    }

    final result = await _apiClient.getByKey(
      'payment.pf',
      fallbackPath: '/api/v1/providentfunds-employee',
      queryParameters: {'employeeId': '$employeeId'},
    );

    if (!result.success) {
      return ApiResult.fail(result.message ?? 'Could not load provident fund.');
    }

    final raw = result.data?['data'];
    if (raw is Map<String, dynamic>) {
      return ApiResult.ok(ProvidentFundRecord.fromJson(raw));
    }
    if (raw == null && result.data != null) {
      // Some HRM responses return the model at top level under unexpected keys.
      return ApiResult.ok(ProvidentFundRecord.fromJson(result.data!));
    }
    return ApiResult.fail('No provident fund record found.');
  }

  Future<ApiResult<List<ProvidentFundRecord>>> getProvidentFundHistory(
    int employeeId,
  ) async {
    if (useDemoData) {
      return ApiResult.ok(PaymentsDemoData.providentFundHistory());
    }

    final result = await _apiClient.getByKey(
      'payment.pf.history',
      fallbackPath: '/api/v1/providentfunds',
      queryParameters: {'employeeId': '$employeeId'},
    );

    if (!result.success) {
      return ApiResult.fail(result.message ?? 'Could not load PF history.');
    }

    final items = _extractList(result.data);
    return ApiResult.ok(items.map(ProvidentFundRecord.fromJson).toList());
  }

  Future<ApiResult<MessDepositRecord>> getMessDeposit(int employeeId) async {
    if (useDemoData) {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      return ApiResult.ok(PaymentsDemoData.messDeposit());
    }

    final result = await _apiClient.getByKey(
      'payment.mess',
      fallbackPath: '/api/v1/mess-deposit-employee',
      queryParameters: {'employeeId': '$employeeId'},
    );

    if (!result.success) {
      return ApiResult.fail(result.message ?? 'Could not load mess deposit.');
    }

    final raw = result.data?['data'];
    if (raw is Map<String, dynamic>) {
      return ApiResult.ok(MessDepositRecord.fromJson(raw));
    }
    if (raw is List && raw.isNotEmpty && raw.first is Map<String, dynamic>) {
      return ApiResult.ok(
        MessDepositRecord.fromJson(raw.first as Map<String, dynamic>),
      );
    }
    return ApiResult.fail('No mess deposit found.');
  }

  Future<ApiResult<CompensationFacility>> getCompensation(
    int employeeId,
  ) async {
    if (useDemoData) {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      return ApiResult.ok(PaymentsDemoData.compensation());
    }

    final result = await _apiClient.getByKey(
      'payment.facility',
      fallbackPath: '/api/v1/facility-employee',
      queryParameters: {'employeeId': '$employeeId'},
    );

    if (!result.success) {
      return ApiResult.fail(result.message ?? 'Could not load compensation.');
    }

    final raw = result.data?['data'];
    if (raw is Map<String, dynamic>) {
      return ApiResult.ok(CompensationFacility.fromJson(raw));
    }
    if (raw is List && raw.isNotEmpty && raw.first is Map<String, dynamic>) {
      return ApiResult.ok(
        CompensationFacility.fromJson(raw.first as Map<String, dynamic>),
      );
    }
    return ApiResult.fail('No compensation facility found.');
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
