import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../config/app_config.dart';
import '../data/payments_demo_data.dart';
import '../models/api_result.dart';
import '../models/auth_wise_payment_models.dart';
import '../models/auth_wise_payment_post_models.dart';
import '../models/payment_setup_models.dart';
import '../models/payment_models.dart';
import '../models/payment_report_failure.dart';
import '../utils/multipart_form.dart';
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
      _configService.isFeatureEnabled('payment.enabled', defaultValue: true);

  Future<String> _salesApiBase() async {
    final fromPersonSales = await _configService.resolveUrl('sales.personSales');
    if (fromPersonSales != null && fromPersonSales.isNotEmpty) {
      final uri = Uri.parse(fromPersonSales);
      return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
    }
    return AppConfig.salesApiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  }

  /// Banks, auth-wise employees, payment types for receive-payment form.
  Future<ApiResult<PaymentSetupData>> fetchPaymentSetupData() async {
    final url = await _configService.resolveUrl('payment.setupData');
    final base = await _salesApiBase();
    final uri = Uri.parse(
      url ?? '$base/api/payment-setup-data',
    );

    try {
      final response = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'PPHLAttendance/2.2 (Android; Flutter)',
            },
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ApiResult.fail(
          'Could not load payment setup (${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return ApiResult.fail('Invalid payment setup response.');
      }

      if (decoded['success'] == false) {
        return ApiResult.fail(
          decoded['message']?.toString() ?? 'Could not load payment setup.',
        );
      }

      final data = decoded['data'];
      if (data is! Map<String, dynamic>) {
        return ApiResult.fail('Invalid payment setup payload.');
      }

      return ApiResult.ok(PaymentSetupData.fromJson(data));
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }
  }

  /// Whether the logged-in HRM employee is listed as an auth-wise receiver.
  Future<ApiResult<void>> checkAuthWiseReceiverEligibility(int employeeId) async {
    if (employeeId <= 0) {
      return ApiResult.fail('Please login again to load dealer payments.');
    }

    final setup = await fetchPaymentSetupData();
    if (!setup.success || setup.data == null) {
      return ApiResult.fail(
        setup.message ?? 'Could not verify payment eligibility.',
      );
    }

    final listed = setup.data!.employees
        .any((employee) => employee.employeeId == employeeId);
    if (!listed) {
      return ApiResult.fail(
        'You are not registered as an auth-wise payment receiver.',
        isSetupIssue: true,
        detail: 'Contact admin to add you as an auth-wise payment receiver.',
      );
    }

    return ApiResult.ok(null);
  }

  /// Live dealer payment-receive report (no JWT). Gated by [isPaymentEnabled].
  Future<ApiResult<AuthWisePaymentsData>> getAuthWisePayments({
    required int employeeId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    if (!await isPaymentEnabled()) {
      return ApiResult.fail('feature_disabled');
    }

    if (employeeId <= 0) {
      return ApiResult.fail('Missing employee profile.');
    }

    final base = (await _configService.resolveUrl('payment.authWise')) ??
        '${AppConfig.salesApiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/api/auth-wise-payments';

    final fmt = DateFormat('yyyy-MM-dd');
    final uri = Uri.parse('$base/$employeeId').replace(
      queryParameters: {
        'from_date': fmt.format(fromDate),
        'to_date': fmt.format(toDate),
      },
    );

    try {
      final response = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'PPHLAttendance/2.2 (Android; Flutter)',
            },
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        assert(() {
          // ignore: avoid_print
          print(
            'getAuthWisePayments failed: $uri status=${response.statusCode} '
            'body=${response.body}',
          );
          return true;
        }());
        final failure = _parsePaymentReportFailure(
          response.body,
          response.statusCode,
        );
        return ApiResult.fail(
          failure.headline,
          statusCode: failure.statusCode,
          detail: failure.actionHint ?? failure.context,
          isSetupIssue: failure.isSetupIssue,
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return ApiResult.fail('Invalid payments response.');
      }

      if (decoded['success'] == false) {
        final failure = _parsePaymentReportFailure(response.body, null);
        return ApiResult.fail(
          failure.headline,
          statusCode: failure.statusCode,
          detail: failure.actionHint ?? failure.context,
          isSetupIssue: failure.isSetupIssue,
        );
      }

      final data = decoded['data'];
      if (data is! Map<String, dynamic>) {
        return ApiResult.fail('Invalid payments payload.');
      }

      return ApiResult.ok(AuthWisePaymentsData.fromJson(data));
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }
  }

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

  Future<ApiResult<AuthWisePaymentCreated>> postAuthWisePayment(
    CreateAuthWisePaymentRequest request,
  ) async {
    if (!await isPaymentEnabled()) {
      return ApiResult.fail('feature_disabled');
    }

    if (request.employeeId <= 0) {
      return ApiResult.fail('Missing employee profile.');
    }

    final url = await _configService.resolveUrl('payment.authWisePost') ??
        (await _configService.resolveUrl('payment.authWise')) ??
        '${AppConfig.salesApiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/api/auth-wise-payments';

    final uri = Uri.parse(url.replaceAll(RegExp(r'/+$'), ''));

    try {
      final response = await postFormData(
        uri: uri,
        fields: request.toFormFields(),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ApiResult.fail(
          _messageFromBody(response.body) ??
              'Could not submit payment (${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return ApiResult.fail('Invalid payment response.');
      }

      if (decoded['success'] == false) {
        return ApiResult.fail(
          decoded['message']?.toString() ?? 'Could not submit payment.',
        );
      }

      return ApiResult.ok(AuthWisePaymentCreated.fromResponse(decoded));
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }
  }

  String? _messageFromBody(String body, {bool preferErrorField = false}) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error']?.toString().trim();
        final message = decoded['message']?.toString().trim();
        if (preferErrorField) {
          if (error != null && error.isNotEmpty) return error;
          if (message != null && message.isNotEmpty) return message;
        } else {
          if (message != null && message.isNotEmpty) return message;
          if (error != null && error.isNotEmpty) return error;
        }
      }
    } catch (_) {}
    return null;
  }

  PaymentReportFailure _parsePaymentReportFailure(
    String body,
    int? statusCode,
  ) {
    String? errorField;
    String? messageField;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        errorField = decoded['error']?.toString().trim();
        messageField = decoded['message']?.toString().trim();
      }
    } catch (_) {}

    final headline = (errorField != null && errorField.isNotEmpty)
        ? errorField
        : (messageField != null && messageField.isNotEmpty)
            ? messageField
            : 'Could not load payments${statusCode != null ? ' ($statusCode)' : ''}.';

    String? context;
    if (errorField != null &&
        errorField.isNotEmpty &&
        messageField != null &&
        messageField.isNotEmpty &&
        messageField != errorField) {
      context = messageField;
    } else if (errorField == null || errorField.isEmpty) {
      context = null;
    }

    final setupIssue = _isSetupIssue(headline, messageField, statusCode);
    final actionHint = _actionHintForSetupIssue(headline, messageField);

    return PaymentReportFailure(
      headline: headline,
      context: context,
      actionHint: actionHint,
      isSetupIssue: setupIssue,
      statusCode: statusCode,
    );
  }

  bool _isSetupIssue(String headline, String? message, int? statusCode) {
    if (statusCode == 422) return true;
    final combined = '${headline.toLowerCase()} ${message?.toLowerCase() ?? ''}';
    return combined.contains('user account') ||
        combined.contains('sales employee was not found') ||
        headline.contains('ব্যবহারকারী') ||
        headline.contains('employee');
  }

  String? _actionHintForSetupIssue(String headline, String? message) {
    final lower = '${headline.toLowerCase()} ${message?.toLowerCase() ?? ''}';
    if (lower.contains('sales employee was not found')) {
      return 'Ask admin to register your employee on the sales system.';
    }
    if (lower.contains('user account') || headline.contains('ব্যবহারকারী')) {
      return 'Ask admin to link your sales user account.';
    }
    if (lower.contains('not registered') ||
        lower.contains('auth-wise payment receiver')) {
      return 'Contact admin to add you as an auth-wise payment receiver.';
    }
    return null;
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
