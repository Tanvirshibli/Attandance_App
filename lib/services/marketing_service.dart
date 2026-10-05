import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/api_result.dart';
import '../models/booking_form_data_models.dart';
import '../models/marketing_dealer.dart';
import '../models/marketing_models.dart';
import '../utils/user_facing_error.dart';
import 'endpoint_config_service.dart';
import 'permission_service.dart';
import 'image_upload_service.dart';

class MarketingService {
  MarketingService({EndpointConfigService? configService})
    : _configService = configService ?? EndpointConfigService.instance;

  final EndpointConfigService _configService;

  static const _userAgent = 'PPHLAttendance/2.2 (Android; Flutter)';
  static const _headers = {
    'Accept': 'application/json',
    'User-Agent': _userAgent,
  };

  /// Marketing is reachable when the deployment enables the feature **and** the
  /// signed-in user holds at least one of the marketing read permissions.
  ///
  /// Two independent axes, both required. The flag is a deployment-wide switch
  /// from `app-config`; the permission is a per-user grant from HRM. Because
  /// this wrapper is what all 27-odd marketing call sites check, composing them
  /// here means a screen reached by a stale navigation stack or a deep link
  /// still fails closed.
  Future<bool> isMarketingEnabled() async {
    final enabled = await _configService.isFeatureEnabled(
      'marketing.enabled',
      defaultValue: true,
    );
    return enabled &&
        PermissionService.instance.canViewModule('marketing');
  }

  /// Whether the user may file new farms, dealers or markets. Separate from
  /// [isMarketingEnabled] on purpose: an officer may read markets without being
  /// able to add one.
  bool canCreate(String recordType) =>
      PermissionService.instance.canCreateIn(recordType);

  Future<String> _url(String key, String fallbackPath) async {
    final resolved = await _configService.resolveUrl(key);
    if (resolved != null && resolved.isNotEmpty) return resolved;
    final base = AppConfig.attendanceApiBaseUrl.trim().replaceAll(
      RegExp(r'/+$'),
      '',
    );
    return '$base$fallbackPath';
  }

  Future<ApiResult<List<Market>>> listMarkets({
    String? q,
    int? limit,
    int? zoneId,
  }) async {
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
        if (limit != null && limit > 0) 'limit': '$limit',
        if (zoneId != null && zoneId > 0) 'zone_id': '$zoneId',
      },
    );
    return _getList(uri, Market.fromJson);
  }

  /// The organisational pickers from this backend's own context
  /// endpoint.
  ///
  /// The mobile backend merges its curated company master with the
  /// Sales org master — a name held locally wins over the same name
  /// upstream — so this is the list a phone should offer, not the
  /// raw Sales form-data list. Sectors stay a pure Sales read: the
  /// `companyId` edge on each sector row is the cascade.
  ///
  /// The endpoint is public (no JWT), like the dealers proxy, so the
  /// read is one round-trip to the backend the app already talks to.
  Future<ApiResult<MarketingContext>> fetchMarketingContext() async {
    if (!await isMarketingEnabled()) {
      return ApiResult.fail('feature_disabled');
    }

    final base = await _url(
      'marketing.context',
      '/api/v1/mobile/marketing/context',
    );
    final uri = Uri.parse(base);

    return _getObject(uri, (json) => MarketingContext.fromJson(json));
  }

  /// Dealers from the Sales master.
  ///
  /// Backed by the backend's proxy rather than by the app calling Sales directly,
  /// so the cached master is read in one place. Deliberately unfiltered: a Sales
  /// dealer row carries no company or sector edge, and narrowing the picker by the
  /// officer's zone would hide dealers they legitimately trade with. The picker is
  /// searchable instead.
  ///
  /// Returns an empty list when the Sales master is unreachable: an unavailable
  /// master is not an error the officer can act on, and the picker simply offers
  /// nothing.
  Future<ApiResult<List<MarketingDealer>>> listExistingDealers({
    String? query,
    int? limit,
  }) async {
    if (!await isMarketingEnabled()) {
      return ApiResult.fail('feature_disabled');
    }

    final base = await _url(
      'marketing.dealers',
      '/api/v1/mobile/marketing/dealers',
    );
    final uri = Uri.parse(base).replace(
      queryParameters: {
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        if (limit != null && limit > 0) 'limit': '$limit',
      },
    );

    return _getList(uri, (json) => MarketingDealer.fromJson(json));
  }

  /// The next record code to submit with, e.g. `DLR-09260007`.
  ///
  /// [prefix] is one of the server's whitelisted values (`DLR` dealer, `FMR`
  /// farm, `MRK` market); anything else is rejected with 422.
  ///
  /// The sequence is allocated server-side under a row lock, so two field
  /// officers opening a form at the same moment get different numbers. A failure
  /// here means the endpoint is unreachable — flagged [ApiResult.isSetupIssue]
  /// so the caller can keep the code field empty rather than invent one that
  /// might collide.
  Future<ApiResult<String>> nextCode(String prefix) async {
    if (!await isMarketingEnabled()) {
      return ApiResult.fail('feature_disabled');
    }

    final base = await _url(
      'marketing.parties',
      '/api/v1/mobile/marketing/parties',
    );
    final uri = Uri.parse(
      '$base/next-code',
    ).replace(queryParameters: {'prefix': prefix});

    try {
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = _decode(response.body);
        if (decoded is Map && decoded['success'] != false) {
          final data = decoded['data'];
          if (data is Map && data['code'] is String) {
            return ApiResult.ok(data['code'] as String);
          }
        }
      }

      return ApiResult.fail(
        'Could not allocate a code.',
        statusCode: response.statusCode,
        isSetupIssue: true,
      );
    } catch (e) {
      return ApiResult.fail(UserFacingError.forException(e));
    }
  }

  /// Parties whose phone matches [phone], for the uniqueness check.
  ///
  /// The backend `q` filter is a substring LIKE, so this returns candidates
  /// rather than an exact answer — callers compare [Party.phone] themselves
  /// after normalising, which `normalisePhone` handles.
  Future<ApiResult<List<Party>>> findPartiesByPhone(String phone) async {
    final digits = normalisePhone(phone);
    if (digits.length < 4) return ApiResult.ok(const <Party>[]);
    return listParties(q: digits);
  }

  /// Markets whose phone matches [phone], for the uniqueness check.
  Future<ApiResult<List<Market>>> findMarketsByPhone(String phone) async {
    final digits = normalisePhone(phone);
    if (digits.length < 4) return ApiResult.ok(const <Market>[]);
    return listMarkets(q: digits);
  }

  /// Farms matching [query] on name or phone.
  ///
  /// The duplicate check at the top of the Add Farm screen. A farm is identified
  /// by its phone and found by its name, so both are searched at once.
  ///
  /// Filtering happens here rather than through [listParties]' `partyType`
  /// parameter on purpose: that maps to the backend's exact
  /// `where('party_type', …)`, and the farm pool is `('farm','farmer')`, so
  /// passing `party_type=farm` would silently drop every `farmer` row. A single
  /// unfiltered `q` query plus a Dart filter is one round-trip and gets both.
  ///
  /// The backend `q` is a substring `LIKE` over name / trade_name / code /
  /// phone / contact_person / owner_name, so the hits are *candidates*. Callers
  /// that care about an exact number compare with [samePhone] themselves.
  ///
  /// A failed lookup is **not** an empty result. Returning `ok([])` would tell
  /// the Add Farm screen "no such farm exists" and offer to create one — turning
  /// a network blip into a duplicate record. The failure is passed through so
  /// the screen can say it could not check.
  Future<ApiResult<List<Party>>> searchFarms(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return ApiResult.ok(const <Party>[]);

    final result = await listParties(q: trimmed, limit: 50);
    if (!result.success) return result;

    final farms = (result.data ?? const <Party>[])
        .where((p) => p.isFarm)
        .toList();
    return ApiResult.ok(farms, statusCode: result.statusCode);
  }

  /// Every farm, for the Add Farm screen's browse list.
  ///
  /// The screen offers the officer the farms already on file before they type
  /// anything, so the list is fetched once on focus and narrowed in Dart as
  /// they type. Re-querying the server per keystroke would put a network
  /// round-trip between every character on a list the device already holds.
  ///
  /// Zone narrowing is **not** applied here. Zone is this employee's own
  /// territory and the caller has to apply it with the same
  /// `ZoneScope.matches` predicate the party list screen uses — including the
  /// market-district fallback for farms created before zone tagging — so the
  /// two lists agree on who is in scope.
  Future<ApiResult<List<Party>>> listFarms({int limit = 200}) async {
    final result = await listParties(limit: limit);
    if (!result.success) return result;

    final farms = (result.data ?? const <Party>[])
        .where((p) => p.isFarm)
        .toList()
      ..sort(
        (a, b) => a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        ),
      );
    return ApiResult.ok(farms, statusCode: result.statusCode);
  }

  /// Reduce a phone number to comparable digits.
  ///
  /// `01712-345678`, `+8801712345678` and `01712345678` are the same dealer, so
  /// a uniqueness check that compared the raw strings would let one number be
  /// registered three times. Drops a `+88` country code, then a national
  /// leading `0`, and keeps everything else — including letters, so a name in
  /// the phone field cannot silently become a match.
  static String normalisePhone(String phone) {
    var digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.startsWith('+88')) {
      digits = digits.substring(3);
    } else if (digits.startsWith('0088')) {
      digits = digits.substring(4);
    }
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return digits;
  }

  /// True when [a] and [b] are the same phone number after normalisation.
  static bool samePhone(String? a, String? b) {
    final left = normalisePhone(a ?? '');
    final right = normalisePhone(b ?? '');
    if (left.isEmpty || right.isEmpty) return false;
    return left == right;
  }

  Future<ApiResult<Market>> createMarket(Map<String, dynamic> payload) async {
    if (!await isMarketingEnabled()) {
      return ApiResult.fail('feature_disabled');
    }
    final url = await _url(
      'marketing.markets',
      '/api/v1/mobile/marketing/markets',
    );
    return _postObject(
      uri: Uri.parse(url),
      body: payload,
      parse: Market.fromJson,
    );
  }

  /// Fetch one market, with its attachments inlined. Mirrors `getParty`.
  Future<ApiResult<Market>> getMarket(int marketId) async {
    if (!await isMarketingEnabled()) {
      return ApiResult.fail('feature_disabled');
    }
    if (marketId <= 0) return ApiResult.fail('Invalid market.');
    final base = await _url(
      'marketing.markets',
      '/api/v1/mobile/marketing/markets',
    );
    return _getObject(Uri.parse('$base/$marketId'), Market.fromJson);
  }

  /// Update market intel + identity (any logged-in employee; the backend
  /// stamps `updated_by_employee_id` from `employee_id`).
  Future<ApiResult<Market>> updateMarket(
    int marketId,
    Map<String, dynamic> payload,
  ) async {
    if (!await isMarketingEnabled()) {
      return ApiResult.fail('feature_disabled');
    }
    if (marketId <= 0) return ApiResult.fail('Invalid market.');
    final base = await _url(
      'marketing.markets',
      '/api/v1/mobile/marketing/markets',
    );
    return _putObject(
      uri: Uri.parse('$base/$marketId'),
      body: payload,
      parse: Market.fromJson,
    );
  }

  Future<ApiResult<List<Party>>> listParties({
    int? employeeId,
    String? partyType,
    String? q,
    String? status,
    int? marketId,
    int? zoneId,
    int? limit,
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
    if (zoneId != null && zoneId > 0) {
      params['zone_id'] = '$zoneId';
    }
    if (limit != null && limit > 0) {
      params['limit'] = '$limit';
    }
    final uri = Uri.parse(base).replace(queryParameters: params);
    return _getList(uri, Party.fromJson);
  }

  /// Load several party types at once and merge them into one result.
  ///
  /// The API filters `party_type` **exactly** and takes a single value, so a
  /// "pool" has to be fetched type by type. The dealer pool is
  /// `('dealer','outlet')` — an officer choosing "Existing dealer" stores the row
  /// as an `outlet`, which a bare `party_type=dealer` query never returns — and
  /// the farm pool is `('farm','farmer')`. Succeeds when at least one type came
  /// back, so one flaky call cannot blank the whole list.
  Future<ApiResult<List<Party>>> listPartiesPool(
    List<String> partyTypes, {
    int? limit,
  }) async {
    final merged = <Party>[];
    var anySuccess = false;
    String? failureMessage;

    for (final type in partyTypes) {
      final result = await listParties(partyType: type, limit: limit);
      if (result.success) {
        anySuccess = true;
        merged.addAll(result.data ?? const <Party>[]);
      } else {
        failureMessage ??= result.message;
      }
    }

    return anySuccess
        ? ApiResult.ok(merged)
        : ApiResult.fail(failureMessage ?? 'Could not load parties.');
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
    return _postObject(
      uri: Uri.parse(url),
      body: payload,
      parse: Party.fromJson,
    );
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
    int? zoneId,
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
    if (zoneId != null && zoneId > 0) params['zone_id'] = '$zoneId';
    if (status != null && status.isNotEmpty && status.toLowerCase() != 'all') {
      params['status'] = status.toLowerCase();
    }
    final uri = Uri.parse(base).replace(queryParameters: params);
    return _getList(uri, Visit.fromJson);
  }

  Future<ApiResult<Visit>> getVisit(int visitId) async {
    if (!await isMarketingEnabled()) {
      return ApiResult.fail('feature_disabled');
    }
    if (visitId <= 0) return ApiResult.fail('Invalid visit.');
    final base = await _url(
      'marketing.visits',
      '/api/v1/mobile/marketing/visits',
    );
    return _getObject(Uri.parse('$base/$visitId'), Visit.fromJson);
  }

  Future<ApiResult<List<Attachment>>> listAttachments({
    required String attachableType,
    required int attachableId,
  }) async {
    if (!await isMarketingEnabled()) {
      return ApiResult.fail('feature_disabled');
    }
    if (attachableId <= 0) return ApiResult.fail('Invalid attachable.');
    final base = await _url(
      'marketing.attachments',
      '/api/v1/mobile/marketing/attachments',
    );
    final uri = Uri.parse(base).replace(
      queryParameters: {
        'attachable_type': attachableType,
        'attachable_id': '$attachableId',
      },
    );
    return _getList(uri, Attachment.fromJson);
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
      body: {'check_in_lat': ?lat, 'check_in_lng': ?lng},
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
      body: {'check_out_lat': ?lat, 'check_out_lng': ?lng, ...?extra},
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
    int? zoneId,
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
    if (zoneId != null && zoneId > 0) params['zone_id'] = '$zoneId';
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

  /// Uploads photos converted to compressed WebP inside the `image[]` field.
  /// The backend also re-encodes to WebP; the wire format is already small.
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

    final imageService = ImageUploadService();
    final webpFiles = await imageService.convertAllToWebp(photos);
    if (webpFiles.isEmpty) {
      return ApiResult.fail('Could not process the selected photos.');
    }

    try {
      final request = http.MultipartRequest('POST', Uri.parse(url));
      request.headers.addAll(_headers);
      request.fields['attachable_type'] = attachableType;
      request.fields['attachable_id'] = '$attachableId';
      request.fields['employee_id'] = '$employeeId';
      request.fields['uploaded_by_employee_id'] = '$employeeId';

      request.files.addAll(await imageService.imageParts(webpFiles));

      final streamed = await request.send().timeout(
        const Duration(seconds: 90),
      );
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ApiResult.fail(
          UserFacingError.forSubmit(
            statusCode: response.statusCode,
            rawMessage: _errorMessage(response),
          ),
          statusCode: response.statusCode,
        );
      }
      final decoded = _decode(response.body);
      final list = marketingExtractList(decoded);
      return ApiResult.ok(list.map(Attachment.fromJson).toList());
    } catch (error) {
      return ApiResult.fail(UserFacingError.forException(error));
    } finally {
      await imageService.cleanupAll(webpFiles);
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
        return _failFrom(response);
      }
      final decoded = _decode(response.body);
      if (decoded is Map && decoded['success'] == false) {
        return ApiResult.fail(
          UserFacingError.forSubmit(
            statusCode: response.statusCode,
            rawMessage: decoded['message']?.toString(),
          ),
          statusCode: response.statusCode,
        );
      }
      final list = marketingExtractList(decoded);
      return ApiResult.ok(list.map(parse).toList());
    } catch (error) {
      return ApiResult.fail(UserFacingError.forException(error));
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
      return ApiResult.fail(UserFacingError.forException(error));
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
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 45));
      return _parseObjectResponse(response, parse);
    } catch (error) {
      return ApiResult.fail(UserFacingError.forException(error));
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
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 45));
      return _parseObjectResponse(response, parse);
    } catch (error) {
      return ApiResult.fail(UserFacingError.forException(error));
    }
  }

  ApiResult<T> _failFrom<T>(http.Response response) {
    return ApiResult.fail(
      UserFacingError.forSubmit(
        statusCode: response.statusCode,
        rawMessage: _errorMessage(response),
      ),
      statusCode: response.statusCode,
    );
  }

  ApiResult<T> _parseObjectResponse<T>(
    http.Response response,
    T Function(Map<String, dynamic>) parse,
  ) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return _failFrom(response);
    }
    final decoded = _decode(response.body);
    if (decoded is Map && decoded['success'] == false) {
      return ApiResult.fail(
        UserFacingError.forSubmit(
          statusCode: response.statusCode,
          rawMessage: decoded['message']?.toString(),
        ),
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
