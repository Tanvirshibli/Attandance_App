import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../data/sales_demo_data.dart';
import '../models/api_result.dart';
import '../models/sales_models.dart';
import 'auth_service.dart';
import 'endpoint_config_service.dart';
import 'hrm_api_client.dart';

export '../models/sales_models.dart' show SalesProfile;

class SalesService {
  SalesService({
    AuthService? authService,
    EndpointConfigService? configService,
    HrmApiClient? apiClient,
  })  : _authService = authService ?? AuthService(),
        _configService = configService ?? EndpointConfigService.instance,
        _apiClient = apiClient ?? HrmApiClient();

  final AuthService _authService;
  final EndpointConfigService _configService;
  final HrmApiClient _apiClient;

  bool get useDemoData => AppConfig.useSalesDemoData;

  Future<bool> isSalesEnabled() =>
      _configService.isFeatureEnabled('sales.enabled', defaultValue: false);

  Future<ApiResult<SalesProfile>> checkEligibility(int? employeeId) async {
    if (useDemoData) {
      return ApiResult.ok(
        SalesProfile(
          isEligible: true,
          employeeName: 'Demo Sales Person',
        ),
      );
    }

    if (!await isSalesEnabled()) {
      return ApiResult.ok(const SalesProfile(isEligible: false));
    }

    if (employeeId == null || employeeId <= 0) {
      return ApiResult.ok(const SalesProfile(isEligible: false));
    }

    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      return ApiResult.fail('Please login to continue.');
    }

    final url = await _configService.resolveUrl('sales.eligibility') ??
        AppConfig.salesEmployeeListUrl;

    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
              'User-Agent': 'PPHLAttendance/2.1 (Android; Flutter)',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return ApiResult.fail('Could not verify sales eligibility.');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return ApiResult.ok(const SalesProfile(isEligible: false));
      }

      final data = decoded['data'];
      if (data is! List) {
        return ApiResult.ok(const SalesProfile(isEligible: false));
      }

      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        final id = item['employeeId'];
        final parsedId = id is int ? id : int.tryParse(id?.toString() ?? '');
        if (parsedId == employeeId) {
          return ApiResult.ok(
            SalesProfile(
              isEligible: true,
              employeeName: item['employeeName']?.toString(),
            ),
          );
        }
      }

      return ApiResult.ok(const SalesProfile(isEligible: false));
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }
  }

  Future<ApiResult<SalesOverview>> getOverview({
    required int employeeId,
    required String period,
  }) async {
    if (useDemoData) {
      await Future<void>.delayed(const Duration(milliseconds: 280));
      return ApiResult.ok(SalesDemoData.overviewForPeriod(period));
    }

    final periodKey = _periodQuery(period);
    final result = await _apiClient.getByKey(
      'sales.overview',
      fallbackPath: '/api/v1/mobile/sales/overview',
      queryParameters: {
        'employeeId': '$employeeId',
        'period': periodKey,
      },
    );

    if (!result.success) {
      return ApiResult.fail(result.message ?? 'Could not load sales overview.');
    }

    final raw = result.data?['data'];
    if (raw is Map<String, dynamic>) {
      return ApiResult.ok(SalesOverview.fromJson(raw));
    }
    return ApiResult.fail('Invalid sales overview response.');
  }

  Future<ApiResult<List<SalePosting>>> getMyPostings({
    required int employeeId,
    String? from,
    String? to,
  }) async {
    if (useDemoData) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return ApiResult.ok(SalesDemoData.postings(employeeId: employeeId));
    }

    final params = <String, String>{'employeeId': '$employeeId'};
    if (from != null && from.isNotEmpty) params['from'] = from;
    if (to != null && to.isNotEmpty) params['to'] = to;

    final result = await _apiClient.getByKey(
      'sales.list',
      fallbackPath: '/api/v1/mobile/sales/postings',
      queryParameters: params,
    );

    if (!result.success) {
      return ApiResult.fail(result.message ?? 'Could not load sales postings.');
    }

    final items = _extractList(result.data);
    return ApiResult.ok(items.map(SalePosting.fromJson).toList());
  }

  Future<ApiResult<SalePosting>> createSale(CreateSaleRequest request) async {
    if (useDemoData) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return ApiResult.ok(SalesDemoData.addPosting(request));
    }

    final result = await _apiClient.postByKey(
      'sales.create',
      fallbackPath: '/api/v1/mobile/sales/postings',
      body: request.toJson(),
    );

    if (!result.success) {
      return ApiResult.fail(result.message ?? 'Could not submit sale.');
    }

    final raw = result.data?['data'];
    if (raw is Map<String, dynamic>) {
      return ApiResult.ok(SalePosting.fromJson(raw));
    }

    return ApiResult.ok(
      SalePosting(
        id: 0,
        employeeId: request.employeeId,
        saleDate: request.saleDate,
        amount: request.amount,
        customerName: request.customerName,
        productName: request.productName,
        quantity: request.quantity,
        notes: request.notes,
      ),
    );
  }

  String _periodQuery(String period) {
    switch (period) {
      case 'Last month':
        return 'last_month';
      case 'Custom':
        return 'custom';
      case 'This month':
      default:
        return 'this_month';
    }
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
