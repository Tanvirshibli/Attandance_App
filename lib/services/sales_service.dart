import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/api_result.dart';
import 'auth_service.dart';
import 'endpoint_config_service.dart';

class SalesProfile {
  const SalesProfile({
    required this.isEligible,
    this.employeeName,
  });

  final bool isEligible;
  final String? employeeName;
}

class SalesService {
  SalesService({
    AuthService? authService,
    EndpointConfigService? configService,
  })  : _authService = authService ?? AuthService(),
        _configService = configService ?? EndpointConfigService.instance;

  final AuthService _authService;
  final EndpointConfigService _configService;

  Future<bool> isSalesEnabled() =>
      _configService.isFeatureEnabled('sales.enabled', defaultValue: false);

  Future<ApiResult<SalesProfile>> checkEligibility(int? employeeId) async {
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
}
