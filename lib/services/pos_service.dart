import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/api_result.dart';
import '../models/pos_models.dart';
import 'endpoint_config_service.dart';

/// Public sales-API client for POS Invoice / POS Challan data.
///
/// The endpoints are guard-free by design (`/api/public/feed-orders/pos...`),
/// so no auth header is sent and no session is required.
class PosService {
  PosService({EndpointConfigService? configService, http.Client? client})
      : _configService = configService ?? EndpointConfigService.instance,
        _client = client ?? http.Client();

  final EndpointConfigService _configService;
  final http.Client _client;

  static const Map<String, String> _headers = {
    'Accept': 'application/json',
    'User-Agent': 'PPHLAttendance/2.6 (Android; Flutter)',
  };

  String get _base =>
      AppConfig.salesApiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  Future<String> _url(String key, String fallbackPath) async {
    return (await _configService.resolveUrl(key)) ?? '$_base$fallbackPath';
  }

  Future<ApiResult<PosOrdersPage>> getOrders({
    String? sector,
    String? category,
    int? categoryId,
    int? subCategoryId,
    int? childCategoryId,
    DateTime? startDate,
    DateTime? endDate,
    int page = 1,
    int limit = 20,
  }) async {
    final query = <String, String>{
      'page': '$page',
      'limit': '$limit',
    };

    if (sector != null && sector.trim().isNotEmpty) query['sector'] = sector.trim();
    if (category != null && category.trim().isNotEmpty) {
      query['category'] = category.trim();
    }
    if (categoryId != null) query['categoryId'] = '$categoryId';
    if (subCategoryId != null) query['subCategoryId'] = '$subCategoryId';
    if (childCategoryId != null) query['childCategoryId'] = '$childCategoryId';
    if (startDate != null) query['startDate'] = _dateOnly(startDate);
    if (endDate != null) query['endDate'] = _dateOnly(endDate);

    final url = Uri.parse(
      await _url('sales.pos.orders', '/api/public/feed-orders/pos'),
    ).replace(queryParameters: query);

    final decoded = await _getJson(url);
    if (!decoded.success) {
      return ApiResult.fail(decoded.message ?? 'Could not load orders.',
          statusCode: decoded.statusCode);
    }

    final map = decoded.data;
    if (map == null) {
      return ApiResult.fail('Invalid orders payload.');
    }

    final data = map['data'];
    final meta = map['meta'];

    return ApiResult.ok(
      PosOrdersPage(
        orders: data is List
            ? data
                .whereType<Map>()
                .map((e) => PosOrderSummary.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : const [],
        meta: meta is Map
            ? PosOrdersMeta.fromJson(Map<String, dynamic>.from(meta))
            : const PosOrdersMeta(),
      ),
    );
  }

  Future<ApiResult<PosOrderDetail>> getOrder(int id) async {
    final url = Uri.parse(
      await _url('sales.pos.order', '/api/public/feed-orders/pos/$id'),
    );

    final decoded = await _getJson(url);
    if (!decoded.success) {
      return ApiResult.fail(decoded.message ?? 'Could not load the order.',
          statusCode: decoded.statusCode);
    }

    final map = decoded.data;
    final data = map?['data'];
    if (data is! Map) {
      return ApiResult.fail('Invalid order payload.');
    }

    return ApiResult.ok(PosOrderDetail.fromJson(Map<String, dynamic>.from(data)));
  }

  Future<ApiResult<List<PosSector>>> getSectors() async {
    final url = Uri.parse(
      await _url('sales.pos.sectors', '/api/public/feed-order-sectors'),
    );

    return _getList(url, PosSector.fromJson, 'Could not load sales points.');
  }

  Future<ApiResult<List<PosCategory>>> getCategories() async {
    final url = Uri.parse(
      await _url('sales.pos.categories', '/api/public/feed-order-categories'),
    );

    return _getList(url, PosCategory.fromJson, 'Could not load categories.');
  }

  Future<ApiResult<List<T>>> _getList<T>(
    Uri url,
    T Function(Map<String, dynamic>) fromJson,
    String failureMessage,
  ) async {
    final decoded = await _getJson(url);
    if (!decoded.success) {
      return ApiResult.fail(decoded.message ?? failureMessage,
          statusCode: decoded.statusCode);
    }

    final data = decoded.data?['data'];
    if (data is! List) {
      return ApiResult.fail('Invalid response payload.');
    }

    return ApiResult.ok(
      data
          .whereType<Map>()
          .map((e) => fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Future<ApiResult<Map<String, dynamic>>> _getJson(Uri url) async {
    try {
      final response =
          await _client.get(url, headers: _headers).timeout(const Duration(seconds: 30));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ApiResult.fail(
          'Request failed (${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return ApiResult.fail('Invalid response.');
      }

      final map = Map<String, dynamic>.from(decoded);
      if (map['success'] == false) {
        return ApiResult.fail(
          map['message']?.toString() ?? 'Request failed.',
          statusCode: response.statusCode,
        );
      }

      return ApiResult.ok(map, statusCode: response.statusCode);
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }
  }

  static String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
