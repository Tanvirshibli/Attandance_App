import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/api_result.dart';
import 'auth_service.dart';
import 'endpoint_config_service.dart';

class HrmApiClient {
  HrmApiClient({AuthService? authService, EndpointConfigService? configService})
      : _authService = authService ?? AuthService(),
        _configService = configService ?? EndpointConfigService.instance;

  final AuthService _authService;
  final EndpointConfigService _configService;

  static const String _userAgent = 'PPHLAttendance/2.1 (Android; Flutter)';

  Future<Map<String, String>> _authHeaders({bool jsonBody = false}) async {
    final token = await _authService.getToken();
    return {
      'Accept': 'application/json',
      if (jsonBody) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      'User-Agent': _userAgent,
    };
  }

  Future<String> _resolveEndpoint(String endpointKey, String fallbackPath) async {
    final url = await _configService.resolveUrl(endpointKey);
    if (url != null && url.isNotEmpty) {
      return url;
    }
    return '${AppConfig.backendApiBaseUrl}$fallbackPath';
  }

  Future<ApiResult<Map<String, dynamic>>> getByKey(
    String endpointKey, {
    required String fallbackPath,
    Map<String, String>? queryParameters,
  }) async {
    final uri = Uri.parse(
      await _resolveEndpoint(endpointKey, fallbackPath),
    ).replace(queryParameters: queryParameters);
    return _getUri(uri);
  }

  Future<ApiResult<Map<String, dynamic>>> postByKey(
    String endpointKey, {
    required String fallbackPath,
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse(await _resolveEndpoint(endpointKey, fallbackPath));
    return _postUri(uri, body: body);
  }

  Future<ApiResult<Map<String, dynamic>>> getJson(
    String path, {
    Map<String, String>? queryParameters,
    String? baseUrl,
  }) async {
    final uri = Uri.parse('${baseUrl ?? AppConfig.backendApiBaseUrl}$path')
        .replace(queryParameters: queryParameters);
    return _getUri(uri);
  }

  Future<ApiResult<Map<String, dynamic>>> postJson(
    String path, {
    Map<String, dynamic>? body,
    String? baseUrl,
  }) async {
    final uri = Uri.parse('${baseUrl ?? AppConfig.backendApiBaseUrl}$path');
    return _postUri(uri, body: body);
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

    Future<ApiResult<Map<String, dynamic>>> sendOnce() async {
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(await _authHeaders());
      request.fields.addAll(fields);
      request.files.addAll(files);

      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);
      return _mapResponse(response);
    }

    try {
      final first = await sendOnce();
      if (first.statusCode != 401) {
        return first;
      }

      final refreshed = await _authService.refreshToken();
      if (!refreshed) {
        await _authService.logout(invalidateServerSession: false);
        return ApiResult.fail('Session expired. Please login again.', statusCode: 401);
      }
      return sendOnce();
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> _getUri(Uri uri) async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      return ApiResult.fail('Please login to continue.');
    }

    try {
      var response = await http
          .get(uri, headers: await _authHeaders())
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 401) {
        final refreshed = await _authService.refreshToken();
        if (!refreshed) {
          await _authService.logout(invalidateServerSession: false);
          return ApiResult.fail(
            'Session expired. Please login again.',
            statusCode: 401,
          );
        }
        response = await http
            .get(uri, headers: await _authHeaders())
            .timeout(const Duration(seconds: 20));
      }

      return _mapResponse(response);
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> _postUri(
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      return ApiResult.fail('Please login to continue.');
    }

    try {
      var response = await http
          .post(
            uri,
            headers: await _authHeaders(jsonBody: true),
            body: jsonEncode(body ?? {}),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode == 401) {
        final refreshed = await _authService.refreshToken();
        if (!refreshed) {
          await _authService.logout(invalidateServerSession: false);
          return ApiResult.fail(
            'Session expired. Please login again.',
            statusCode: 401,
          );
        }
        response = await http
            .post(
              uri,
              headers: await _authHeaders(jsonBody: true),
              body: jsonEncode(body ?? {}),
            )
            .timeout(const Duration(seconds: 25));
      }

      return _mapResponse(response);
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }
  }

  ApiResult<Map<String, dynamic>> _mapResponse(http.Response response) {
    final data = _decodeMap(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return ApiResult.ok(data, statusCode: response.statusCode);
    }

    return ApiResult.fail(
      data['message']?.toString() ??
          'Request failed (${response.statusCode}).',
      statusCode: response.statusCode,
    );
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
