import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/api_result.dart';
import 'auth_service.dart';

class HrmApiClient {
  HrmApiClient({AuthService? authService})
      : _authService = authService ?? AuthService();

  final AuthService _authService;

  static const String _userAgent = 'PPHLAttendance/2.0 (Android; Flutter)';

  Future<Map<String, String>> _authHeaders({bool jsonBody = false}) async {
    final token = await _authService.getToken();
    return {
      'Accept': 'application/json',
      if (jsonBody) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      'User-Agent': _userAgent,
    };
  }

  Future<ApiResult<Map<String, dynamic>>> getJson(
    String path, {
    Map<String, String>? queryParameters,
    String? baseUrl,
  }) async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      return ApiResult.fail('Please login to continue.');
    }

    final uri = Uri.parse('${baseUrl ?? AppConfig.backendApiBaseUrl}$path')
        .replace(queryParameters: queryParameters);

    try {
      final response = await http
          .get(uri, headers: await _authHeaders())
          .timeout(const Duration(seconds: 20));

      final data = _decodeMap(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApiResult.ok(data, statusCode: response.statusCode);
      }

      return ApiResult.fail(
        data['message']?.toString() ??
            'Request failed (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> postJson(
    String path, {
    Map<String, dynamic>? body,
    String? baseUrl,
  }) async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      return ApiResult.fail('Please login to continue.');
    }

    final uri = Uri.parse('${baseUrl ?? AppConfig.backendApiBaseUrl}$path');

    try {
      final response = await http
          .post(
            uri,
            headers: await _authHeaders(jsonBody: true),
            body: jsonEncode(body ?? {}),
          )
          .timeout(const Duration(seconds: 25));

      final data = _decodeMap(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApiResult.ok(data, statusCode: response.statusCode);
      }

      return ApiResult.fail(
        data['message']?.toString() ??
            'Request failed (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> postMultipart(
    String path, {
    required Map<String, String> fields,
    List<http.MultipartFile> files = const [],
    String? baseUrl,
  }) async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      return ApiResult.fail('Please login to continue.');
    }

    final uri = Uri.parse('${baseUrl ?? AppConfig.backendApiBaseUrl}$path');

    try {
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(await _authHeaders());
      request.fields.addAll(fields);
      request.files.addAll(files);

      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);
      final data = _decodeMap(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApiResult.ok(data, statusCode: response.statusCode);
      }

      return ApiResult.fail(
        data['message']?.toString() ??
            'Request failed (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }
  }

  Map<String, dynamic> _decodeMap(String responseBody) {
    if (responseBody.isEmpty) return {};
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }
}
