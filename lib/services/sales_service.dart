import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../config/app_config.dart';
import '../data/sales_demo_data.dart';
import '../models/api_result.dart';
import '../models/sales_models.dart';
import 'auth_service.dart';
import 'endpoint_config_service.dart';

export '../models/sales_models.dart' show SalesProfile;

class SalesService {
  SalesService({
    AuthService? authService,
    EndpointConfigService? configService,
  })  : _authService = authService ?? AuthService(),
        _configService = configService ?? EndpointConfigService.instance;

  final AuthService _authService;
  final EndpointConfigService _configService;

  bool get useDemoData => AppConfig.useSalesDemoData;

  /// Post Sale has no live create API yet — always demo.
  bool get useCreateDemo => true;

  Future<bool> isSalesEnabled() =>
      _configService.isFeatureEnabled('sales.enabled', defaultValue: true);

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
      return ApiResult.ok(
        const SalesProfile(
          isEligible: false,
          unavailableReason: SalesProfile.featureDisabled,
        ),
      );
    }

    if (employeeId == null || employeeId <= 0) {
      return ApiResult.ok(
        const SalesProfile(
          isEligible: false,
          unavailableReason: SalesProfile.notOnList,
        ),
      );
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
              'User-Agent': 'PPHLAttendance/2.2 (Android; Flutter)',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return ApiResult.fail('Could not verify sales eligibility.');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return ApiResult.ok(
          const SalesProfile(
            isEligible: false,
            unavailableReason: SalesProfile.notOnList,
          ),
        );
      }

      final data = decoded['data'];
      if (data is! List) {
        return ApiResult.ok(
          const SalesProfile(
            isEligible: false,
            unavailableReason: SalesProfile.notOnList,
          ),
        );
      }

      for (final item in data) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final id = map['employeeId'];
        final parsedId = id is int ? id : int.tryParse(id?.toString() ?? '');
        if (parsedId == employeeId) {
          return ApiResult.ok(
            SalesProfile(
              isEligible: true,
              employeeName: map['employeeName']?.toString(),
            ),
          );
        }
      }

      return ApiResult.ok(
        const SalesProfile(
          isEligible: false,
          unavailableReason: SalesProfile.notOnList,
        ),
      );
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }
  }

  Future<ApiResult<SalesPersonSalesData>> getSalesPersonSales({
    required int employeeId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    if (useDemoData) {
      await Future<void>.delayed(const Duration(milliseconds: 280));
      return ApiResult.ok(
        SalesDemoData.personSales(
          employeeId: employeeId,
          fromDate: fromDate,
          toDate: toDate,
        ),
      );
    }

    final base = (await _configService.resolveUrl('sales.personSales')) ??
        '${AppConfig.salesApiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/api/sales-person-sales';

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
        return ApiResult.fail(
          'Could not load sales (${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return ApiResult.fail('Invalid sales response.');
      }

      if (decoded['success'] == false) {
        return ApiResult.fail(
          decoded['message']?.toString() ?? 'Could not load sales.',
        );
      }

      final data = decoded['data'];
      if (data is! Map<String, dynamic>) {
        return ApiResult.fail('Invalid sales payload.');
      }

      return ApiResult.ok(SalesPersonSalesData.fromJson(data));
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }
  }

  Future<ApiResult<SalePosting>> createSale(CreateSaleRequest request) async {
    // Live create API not available yet — always use in-memory demo store.
    if (useCreateDemo) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return ApiResult.ok(SalesDemoData.addPosting(request));
    }

    return ApiResult.fail('Sale create is not available.');
  }
}
