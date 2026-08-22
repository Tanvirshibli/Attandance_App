import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/api_result.dart';
import '../models/marketing_models.dart';
import 'endpoint_config_service.dart';

class MarketingService {
  MarketingService({EndpointConfigService? configService})
      : _configService = configService ?? EndpointConfigService.instance;

  final EndpointConfigService _configService;

  static const _userAgent = 'PPHLAttendance/2.2 (Android; Flutter)';
  static const _headers = {
    'Accept': 'application/json',
    'User-Agent': _userAgent,
  };

  Future<bool> isMarketingEnabled() =>
      _configService.isFeatureEnabled('marketing.enabled', defaultValue: true);

  Future<String> _url(String key, String fallbackPath) async {
    final resolved = await _configService.resolveUrl(key);
    if (resolved != null && resolved.isNotEmpty) return resolved;
    final base = AppConfig.attendanceApiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return '$base$fallbackPath';
  }

  Future<ApiResult<List<Market>>> listMarkets({String? q}) async {
    if (!await isMarketingEnabled()) {
      return ApiResult.fail('feature_disabled');
    }
    final base = await _url(
      'marketing.markets',
      '/api/v1/mobile/marketing/markets',
    );
    final uri = Uri.parse(base).replace(
      queryParameters: {
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      },
    );
    return _getList(uri, Market.fromJson);
  }

  Future<ApiResult<Market>> createMarket({
    required String name,
    String? code,
    int? companyId,
    int? sectorId,
    String? divisionName,
    String? district,
    String? upazila,
    String? unionName,
    String? villageName,
    String? address,
    double? lat,
    double? lng,
    String? status,
    String? notes,
  }) async {
    if (!await isMarketingEnabled()) {
      return ApiResult.fail('feature_disabled');
    }
    final url = await _url(
      'marketing.markets',
      '/api/v1/mobile/marketing/markets',
    );
    return _postObject(
      uri: Uri.parse(url),
      body: {
        'name': name,
        if (code != null && code.isNotEmpty) 'code': code,
        if (companyId != null && companyId > 0) 'company_id': companyId,
        if (sectorId != null && sectorId > 0) 'sector_id': sectorId,
        if (divisionName != null && divisionName.isNotEmpty)
          'division_name': divisionName,
        if (district != null && district.isNotEmpty) 'district': district,
        if (upazila != null && upazila.isNotEmpty) 'upazila': upazila,
        if (unionName != null && unionName.isNotEmpty) 'union_name': unionName,
        if (villageName != null && villageName.isNotEmpty)
          'village_name': villageName,
        if (address != null && address.isNotEmpty) 'address': address,
        'lat': ?lat,
        'lng': ?lng,
        if (status != null && status.isNotEmpty) 'status': status,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
      parse: Market.fromJson,
    );
  }

  Future<ApiResult<List<Party>>> listParties({
    int? employeeId,
    String? partyType,
    String? q,
    String? status,
    int? marketId,
  }) async {
    if (!await isMarketingEnabled()) {
      return ApiResult.fail('feature_disabled');
    }
    final base = await _url(
      'marketing.parties',
      '/api/v1/mobile/marketing/parties',
    );
    final params = <String, String>{};
    if (employeeId != null && employeeId > 0) {
      params['employee_id'] = '$employeeId';
    }
    if (partyType != null && partyType.isNotEmpty && partyType != 'all') {
      params['party_type'] = partyType;
    }
    if (q != null && q.trim().isNotEmpty) params['q'] = q.trim();
    if (status != null && status.isNotEmpty && status.toLowerCase() != 'all') {
      params['status'] = status.toLowerCase();
    }
    if (marketId != null && marketId > 0) {
      params['market_id'] = '$marketId';
    }
    final uri = Uri.parse(base).replace(queryParameters: params);
    return _getList(uri, Party.fromJson);
  }

  Future<ApiResult<Party>> getParty(int partyId) async {
    if (!await isMarketingEnabled()) {
      return ApiResult.fail('feature_disabled');
    }
    if (partyId <= 0) return ApiResult.fail('Invalid party.');
    final base = await _url(
      'marketing.parties',
      '/api/v1/mobile/marketing/parties',
    );
    return _getObject(Uri.parse('$base/$partyId'), Party.fromJson);
  }

  Future<ApiResult<Party>> createParty(Map<String, dynamic> payload) async {
    if (!await isMarketingEnabled()) {
      return ApiResult.fail('feature_disabled');
    }
    final url = await _url(
      'marketing.party.create',
      '/api/v1/mobile/marketing/parties',
    );
    return _postObject(uri: Uri.parse(url), body: payload, parse: Party.fromJson);
  }

  Future<ApiResult<Party>> updateParty(
    int partyId,
    Map<String, dynamic> payload,
  ) async {
    if (!await isMarketingEnabled()) {
      return ApiResult.fail('feature_disabled');
    }
    if (partyId <= 0) return ApiResult.fail('Invalid party.');
    final base = await _url(
      'marketing.parties',
      '/api/v1/mobile/marketing/parties',
    );
    return _putObject(
      uri: Uri.parse('$base/$partyId'),
      body: payload,
      parse: Party.fromJson,
    );
  }

  Future<ApiResult<List<Visit>>> listVisits({
    int? employeeId,
    int? partyId,
    String? status,
  }) async {
    if (!await isMarketingEnabled()) {
      return ApiResult.fail('feature_disabled');
    }
    final base = await _url(
      'marketing.visits',
      '/api/v1/mobile/marketing/visits',
    );
    final params = <String, String>{};
    if (employeeId != null && employeeId > 0) {
      params['employee_id'] = '$employeeId';
    }
    if (partyId != null && partyId > 0) params['party_id'] = '$partyId';
    if (status != null && status.isNotEmpty && status.toLowerCase() != 'all') {
      params['status'] = status.toLowerCase();
    }
    final uri = Uri.parse(base).replace(queryParameters: params);
    return _getList(uri, Visit.fromJson);
  }

  Future<ApiResult<Visit>> createVisit(Map<String, dynamic> payload) async {
    if (!await isMarketingEnabled()) {
      return ApiResult.fail('feature_disabled');
    }
    final body = Map<String, dynamic>.from(payload);
    body.putIfAbsent('status', () => 'in_progress');
    final url = await _url(
      'marketing.visit.create',
      '/api/v1/mobile/marketing/visits',
    );
    return _postObject(uri: Uri.parse(url), body: body, parse: Visit.fromJson);
  }

  Future<ApiResult<Visit>> checkInVisit(
    int visitId, {
    double? lat,
    double? lng,
  }) async {
    if (!await isMarketingEnabled()) {
      return ApiResult.fail('feature_disabled');
    }
    if (visitId <= 0) return ApiResult.fail('Invalid visit.');
    final base = await _url(
      'marketing.visits',
      '/api/v1/mobile/marketing/visits',
    );
    return _postObject(
      uri: Uri.parse('$base/$visitId/check-in'),
      body: {
        'check_in_lat': ?lat,
        'check_in_lng': ?lng,
      },
      parse: Visit.fromJson,
    );
  }

  Future<ApiResult<Visit>> checkOutVisit(
    int visitId, {
    double? lat,
    double? lng,
    Map<String, dynamic>? extra,
  }) async {
    if (!await isMarketingEnabled()) {
      return ApiResult.fail('feature_disabled');
    }
    if (visitId <= 0) return ApiResult.fail('Invalid visit.');
    final base = await _url(
      'marketing.visits',
      '/api/v1/mobile/marketing/visits',
    );
    return _postObject(
      uri: Uri.parse('$base/$visitId/check-out'),
      body: {
        'check_out_lat': ?lat,
        'check_out_lng': ?lng,
        ...?extra,
      },
      parse: Visit.fromJson,
    );
  }

  Future<ApiResult<Visit>> completeVisit(
    int visitId, {
    Map<String, dynamic>? updates,
  }) async {
    Map<String, dynamic>? extra;
    if (updates != null) {
      extra = Map<String, dynamic>.from(updates);
      extra.remove('check_out_lat');
      extra.remove('check_out_lng');
      extra.remove('lat');
      extra.remove('lng');
    }
    return checkOutVisit(
      visitId,
      lat: marketingParseDouble(updates?['check_out_lat'] ?? updates?['lat']),
      lng: marketingParseDouble(updates?['check_out_lng'] ?? updates?['lng']),
      extra: extra,
    );
  }

  Future<ApiResult<List<FarmSurvey>>> listFarmSurveys({
    int? employeeId,
    int? partyId,
  }) async {
    if (!await isMarketingEnabled()) {
      return ApiResult.fail('feature_disabled');
    }
    final base = await _url(
      'marketing.surveys',
      '/api/v1/mobile/marketing/farm-surveys',
    );
    final params = <String, String>{};
    if (employeeId != null && employeeId > 0) {
      params['employee_id'] = '$employeeId';
    }
    if (partyId != null && partyId > 0) params['party_id'] = '$partyId';
    final uri = Uri.parse(base).replace(queryParameters: params);
    return _getList(uri, FarmSurvey.fromJson);
  }

  Future<ApiResult<FarmSurvey>> getFarmSurvey(int surveyId) async {
    if (!await isMarketingEnabled()) {
      return ApiResult.fail('feature_disabled');
    }
    if (surveyId <= 0) return ApiResult.fail('Invalid survey.');
    final base = await _url(
      'marketing.surveys',
      '/api/v1/mobile/marketing/farm-surveys',
    );
    return _getObject(Uri.parse('$base/$surveyId'), FarmSurvey.fromJson);
  }

  Future<ApiResult<FarmSurvey>> createFarmSurvey(
    Map<String, dynamic> payload,
  ) async {
    if (!await isMarketingEnabled()) {
      return ApiResult.fail('feature_disabled');
    }
    final url = await _url(
      'marketing.survey.create',
      '/api/v1/mobile/marketing/farm-surveys',
    );
    return _postObject(
      uri: Uri.parse(url),
      body: payload,
      parse: FarmSurvey.fromJson,
    );
  }

  Future<ApiResult<List<Followup>>> listFollowups({
    int? employeeId,
    int? partyId,
    String? status,
  }) async {
    if (!await isMarketingEnabled()) {
      return ApiResult.fail('feature_disabled');
    }
    final base = await _url(
      'marketing.followups',
      '/api/v1/mobile/marketing/followups',
    );
    final params = <String, String>{};
    if (employeeId != null && employeeId > 0) {
      params['employee_id'] = '$employeeId';
    }
    if (partyId != null && partyId > 0) params['party_id'] = '$partyId';
    if (status != null && status.isNotEmpty && status.toLowerCase() != 'all') {
      params['status'] = status.toLowerCase();
    }
    final uri = Uri.parse(base).replace(queryParameters: params);
    return _getList(uri, Followup.fromJson);
  }

  Future<ApiResult<Followup>> createFollowup(
    Map<String, dynamic> payload,
  ) async {
    if (!await isMarketingEnabled()) {
      return ApiResult.fail('feature_disabled');
    }
    final url = await _url(
      'marketing.followup.create',
      '/api/v1/mobile/marketing/followups',
    );
    return _postObject(
      uri: Uri.parse(url),
      body: payload,
      parse: Followup.fromJson,
    );
  }

  Future<ApiResult<Followup>> updateFollowup(
    int followupId,
    Map<String, dynamic> payload,
  ) async {
    if (!await isMarketingEnabled()) {
      return ApiResult.fail('feature_disabled');
    }
    if (followupId <= 0) return ApiResult.fail('Invalid follow-up.');
    final base = await _url(
      'marketing.followups',
      '/api/v1/mobile/marketing/followups',
    );
    return _putObject(
      uri: Uri.parse('$base/$followupId'),
      body: payload,
      parse: Followup.fromJson,
    );
  }

  Future<ApiResult<List<Attachment>>> uploadAttachments({
    required String attachableType,
    required int attachableId,
    required int employeeId,
    required List<File> photos,
  }) async {
    if (!await isMarketingEnabled()) {
      return ApiResult.fail('feature_disabled');
    }
    if (photos.isEmpty) {
      return ApiResult.ok(const []);
    }
    final url = await _url(
      'marketing.attachments',
      '/api/v1/mobile/marketing/attachments',
    );

    try {
      final request = http.MultipartRequest('POST', Uri.parse(url));
      request.headers.addAll(_headers);
      request.fields['attachable_type'] = attachableType;
      request.fields['attachable_id'] = '$attachableId';
      request.fields['employee_id'] = '$employeeId';
      request.fields['uploaded_by_employee_id'] = '$employeeId';

      for (final photo in photos) {
        request.files.add(
          await http.MultipartFile.fromPath('photos[]', photo.path),
        );
      }

      final streamed = await request.send().timeout(const Duration(seconds: 90));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ApiResult.fail(
          _errorMessage(response) ??
              'Could not upload photos (${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
      final decoded = _decode(response.body);
      final list = marketingExtractList(decoded);
      return ApiResult.ok(list.map(Attachment.fromJson).toList());
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }
  }

  Future<ApiResult<List<T>>> _getList<T>(
    Uri uri,
    T Function(Map<String, dynamic>) parse,
  ) async {
    try {
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ApiResult.fail(
          _errorMessage(response) ??
              'Request failed (${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
      final decoded = _decode(response.body);
      if (decoded is Map && decoded['success'] == false) {
        return ApiResult.fail(
          decoded['message']?.toString() ?? 'Request failed.',
          statusCode: response.statusCode,
        );
      }
      final list = marketingExtractList(decoded);
      return ApiResult.ok(list.map(parse).toList());
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }
  }

  Future<ApiResult<T>> _getObject<T>(
    Uri uri,
    T Function(Map<String, dynamic>) parse,
  ) async {
    try {
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _parseObjectResponse(response, parse);
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }
  }

  Future<ApiResult<T>> _postObject<T>({
    required Uri uri,
    required Map<String, dynamic> body,
    required T Function(Map<String, dynamic>) parse,
  }) async {
    try {
      final response = await http
          .post(
            uri,
            headers: {
              ..._headers,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 45));
      return _parseObjectResponse(response, parse);
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }
  }

  Future<ApiResult<T>> _putObject<T>({
    required Uri uri,
    required Map<String, dynamic> body,
    required T Function(Map<String, dynamic>) parse,
  }) async {
    try {
      final response = await http
          .put(
            uri,
            headers: {
              ..._headers,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 45));
      return _parseObjectResponse(response, parse);
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }
  }

  ApiResult<T> _parseObjectResponse<T>(
    http.Response response,
    T Function(Map<String, dynamic>) parse,
  ) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return ApiResult.fail(
        _errorMessage(response) ??
            'Request failed (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    final decoded = _decode(response.body);
    if (decoded is Map && decoded['success'] == false) {
      return ApiResult.fail(
        decoded['message']?.toString() ?? 'Request failed.',
        statusCode: response.statusCode,
      );
    }
    final obj = marketingExtractObject(decoded);
    if (obj == null) {
      return ApiResult.fail('Invalid response payload.');
    }
    return ApiResult.ok(
      parse(obj),
      message: decoded is Map ? decoded['message']?.toString() : null,
      statusCode: response.statusCode,
    );
  }

  Object? _decode(String body) {
    if (body.trim().isEmpty) return null;
    return jsonDecode(body);
  }

  String? _errorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final msg = decoded['message']?.toString();
        if (msg != null && msg.isNotEmpty) return msg;
        final errors = decoded['errors'];
        if (errors is Map && errors.isNotEmpty) {
          final first = errors.values.first;
          if (first is List && first.isNotEmpty) return first.first.toString();
          return first.toString();
        }
      }
    } catch (_) {}
    return null;
  }
}
