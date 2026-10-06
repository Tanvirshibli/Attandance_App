import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../config/app_config.dart';
import '../data/sales_demo_data.dart';
import '../models/api_result.dart';
import '../models/booking_form_data_models.dart';
import '../models/sales_models.dart';
import '../models/dealer_list_models.dart';
import '../models/sales_booking_post_models.dart';
import '../models/sales_post_models.dart';
import '../models/zone_models.dart';
import '../utils/multipart_form.dart';
import 'auth_service.dart';
import 'endpoint_config_service.dart';

export '../models/sales_models.dart' show SalesProfile;
export '../models/booking_form_data_models.dart';

class SalesService {
  SalesService({
    AuthService? authService,
    EndpointConfigService? configService,
  })  : _authService = authService ?? AuthService(),
        _configService = configService ?? EndpointConfigService.instance;

  final AuthService _authService;
  final EndpointConfigService _configService;

  AllDealerLists? _cachedDealerLists;
  BookingFormData? _cachedBookingFormData;
  List<SalesZone>? _cachedZoneList;
  SalesProductCatalog? _cachedProductCatalog;
  int? _cachedSalesUserId;

  bool get useDemoData => AppConfig.useSalesDemoData;

  bool get useCreateDemo => useDemoData;

  Future<String> _salesApiBase() async {
    final fromConfig = await _configService.resolveUrl('sales.personSales');
    if (fromConfig != null && fromConfig.isNotEmpty) {
      return fromConfig.replaceAll(RegExp(r'/+$'), '');
    }
    return AppConfig.salesApiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  }

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

  Future<ApiResult<AllDealerLists>> fetchAllDealerLists({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedDealerLists != null) {
      return ApiResult.ok(_cachedDealerLists!);
    }

    if (useDemoData) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      _cachedDealerLists = const AllDealerLists(
        egg: [
          DealerListItem(
            id: 19,
            tradeName: 'Demo Egg Dealer',
            dealerCode: 'DLR250019',
            zoneName: 'Zone D',
          ),
        ],
        feed: [
          DealerListItem(
            id: 100,
            tradeName: 'Demo Feed Dealer',
            dealerCode: 'DLR250100',
            zoneName: 'Zone A',
          ),
        ],
        fertilizer: [],
        liveBird: [],
        wastage: [],
        zones: [
          DealerZone(id: 1, zoneName: 'Zone A'),
          DealerZone(id: 4, zoneName: 'Zone D'),
        ],
      );
      return ApiResult.ok(_cachedDealerLists!);
    }

    final url = await _configService.resolveUrl('sales.allDealers');
    final uri = Uri.parse(
      url ??
          '${AppConfig.salesApiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/api/all-dealer-lists',
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
          .timeout(const Duration(seconds: 60));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ApiResult.fail(
          'Could not load dealers (${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return ApiResult.fail('Invalid dealer lists response.');
      }

      if (decoded['success'] == false) {
        return ApiResult.fail(
          decoded['message']?.toString() ?? 'Could not load dealers.',
        );
      }

      final data = decoded['data'];
      if (data is! Map<String, dynamic>) {
        return ApiResult.fail('Invalid dealer lists payload.');
      }

      _cachedDealerLists = AllDealerLists.fromJson(data);
      return ApiResult.ok(_cachedDealerLists!);
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }
  }

  /// Sales zone master with its districts. Public endpoint — no token — and
  /// cached for the process lifetime because zones change rarely.
  Future<ApiResult<List<SalesZone>>> fetchZoneList({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedZoneList != null) {
      return ApiResult.ok(_cachedZoneList!);
    }

    final url = await _configService.resolveUrl('sales.zoneList');
    final uri = Uri.parse(
      url ??
          '${AppConfig.salesApiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/api/get-zone',
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
          'Could not load zones (${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return ApiResult.fail('Invalid zone list response.');
      }

      _cachedZoneList = SalesZone.listFrom(decoded);
      return ApiResult.ok(_cachedZoneList!);
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }
  }

  /// Companies + sectors from booking form-data (cached for the process lifetime).
  Future<ApiResult<BookingFormData>> fetchBookingFormData({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedBookingFormData != null) {
      return ApiResult.ok(_cachedBookingFormData!);
    }

    if (useDemoData) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      _cachedBookingFormData = const BookingFormData(
        companies: [
          BookingFormCompany(id: 2, nameEn: 'Peoples feed'),
          BookingFormCompany(id: 3, nameEn: 'Peoples poultry & hatchery ltd'),
        ],
        sectors: [
          BookingFormSector(id: 25, name: 'Sanabandha Hatchery', companyId: 3),
          BookingFormSector(id: 26, name: 'Comilla Hatchery', companyId: 3),
        ],
        feedCategories: [BookingFormCategory(id: 1, name: 'Feed')],
        feedSubCategories: [BookingFormSubCategory(id: 1, name: 'Starter')],
        feedChildCategories: [
          BookingFormChildCategory(id: 1, name: 'Broiler', subCategoryId: 1),
        ],
        feedSalesPoints: [
          BookingFormSector(id: 10, name: 'Demo sales point', companyId: 2),
        ],
        feedProductPrices: [
          BookingFormProductPrice(
            productId: 1,
            productName: 'Demo Feed',
            tradePrice: 2100,
            categoryId: 1,
            subCategoryId: 1,
            childCategoryId: 1,
          ),
        ],
        chicksCategories: [BookingFormCategory(id: 2, name: 'Chicks')],
        chicksSectors: [
          BookingFormSector(id: 25, name: 'Sanabandha Hatchery', companyId: 3),
        ],
        chicksProducts: [
          BookingFormChicksProduct(
            sectorId: 25,
            productId: 50,
            productName: 'DOC',
            closingBalance: 1000,
          ),
        ],
      );
      return ApiResult.ok(_cachedBookingFormData!);
    }

    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      return ApiResult.fail('Please login to continue.');
    }

    final url = await _configService.resolveUrl('sales.booking.formData');
    final uri = Uri.parse(
      url ??
          '${AppConfig.salesApiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/api/booking-person-books/form-data',
    );

    try {
      final response = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
              'User-Agent': 'PPHLAttendance/2.2 (Android; Flutter)',
            },
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ApiResult.fail(
          'Could not load form masters (${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return ApiResult.fail('Invalid form-data response.');
      }
      if (decoded['success'] == false) {
        return ApiResult.fail(
          decoded['message']?.toString() ?? 'Could not load form masters.',
        );
      }

      final data = decoded['data'];
      if (data is! Map<String, dynamic>) {
        return ApiResult.fail('Invalid form-data payload.');
      }

      _cachedBookingFormData = BookingFormData.fromApiData(data);
      return ApiResult.ok(_cachedBookingFormData!);
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

    final base = await _salesApiBase();
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

  Future<ApiResult<BookingPersonBookCreated>> createBookingPersonBook(
    CreateBookingPersonBookRequest request,
  ) async {
    if (useCreateDemo) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return ApiResult.ok(
        BookingPersonBookCreated(
          module: request.module,
          id: 0,
          bookingNo: 'DEMO-BK-${DateTime.now().millisecondsSinceEpoch % 100000}',
          status: 'demo',
          totalAmount: request.totalAmount,
          message: 'Demo booking submitted.',
        ),
      );
    }

    if (!await isSalesEnabled()) {
      return ApiResult.fail('Sales module is disabled.');
    }

    final url = await _configService.resolveUrl('sales.booking.create');
    final uri = Uri.parse(
      url ??
          '${AppConfig.salesApiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/api/booking-person-books',
    );

    try {
      final response = await postFormData(
        uri: uri,
        fields: request.toFormFields(),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ApiResult.fail(
          _messageFromBody(response.body) ??
              'Could not submit booking (${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return ApiResult.fail('Invalid booking response.');
      }

      if (decoded['success'] == false) {
        return ApiResult.fail(
          decoded['message']?.toString() ?? 'Could not submit booking.',
        );
      }

      final data = decoded['data'];
      if (data is! Map<String, dynamic>) {
        return ApiResult.fail('Invalid booking payload.');
      }

      final created = BookingPersonBookCreated.fromJson(data);
      return ApiResult.ok(
        BookingPersonBookCreated(
          module: created.module,
          id: created.id,
          bookingNo: created.bookingNo,
          status: created.status,
          totalAmount: created.totalAmount,
          message: decoded['message']?.toString(),
        ),
      );
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }
  }

  Future<ApiResult<SalesPersonOrderCreated>> createSalesPersonOrder(
    CreateSalesPersonOrderRequest request,
  ) async {
    if (useCreateDemo) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return ApiResult.ok(
        SalesPersonOrderCreated(
          module: request.module,
          id: 0,
          referenceNo: 'DEMO-${DateTime.now().millisecondsSinceEpoch}',
          status: 'demo',
          salesPerson: request.salesPersonId,
          totalAmount: request.totalAmount,
          message: 'Demo order (enable live sales reporting to post).',
        ),
      );
    }

    if (!await isSalesEnabled()) {
      return ApiResult.fail('Sales module is disabled.');
    }

    final url = await _configService.resolveUrl('sales.create');
    final uri = Uri.parse(
      url ??
          '${AppConfig.salesApiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/api/sales-person-sales',
    );

    try {
      final response = await postFormData(
        uri: uri,
        fields: request.toFormFields(),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ApiResult.fail(
          _messageFromBody(response.body) ??
              'Could not submit sale (${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return ApiResult.fail('Invalid sale response.');
      }

      if (decoded['success'] == false) {
        return ApiResult.fail(
          decoded['message']?.toString() ?? 'Could not submit sale.',
        );
      }

      final data = decoded['data'];
      if (data is! Map<String, dynamic>) {
        return ApiResult.fail('Invalid sale payload.');
      }

      final created = SalesPersonOrderCreated.fromJson(data);
      return ApiResult.ok(
        SalesPersonOrderCreated(
          module: created.module,
          id: created.id,
          referenceNo: created.referenceNo,
          status: created.status,
          salesPerson: created.salesPerson,
          totalAmount: created.totalAmount,
          message: decoded['message']?.toString(),
        ),
      );
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }
  }

  /// Legacy demo Post Sale — kept for compatibility.
  Future<ApiResult<SalePosting>> createSale(CreateSaleRequest request) async {
    if (useCreateDemo) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return ApiResult.ok(SalesDemoData.addPosting(request));
    }

    return ApiResult.fail('Use createSalesPersonOrder for live posting.');
  }

  String? _messageFromBody(String body) => submitErrorMessage(body);

  /// The message to show for a failed submit body.
  ///
  /// A 422 from the booking validator puts the useful text on `errors`
  /// ("Booking person is required.") while `message` is the generic
  /// "Validation failed." — prefers the field error so the toast is actionable.
  static String? submitErrorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final errors = decoded['errors'];
        if (errors is Map) {
          for (final value in errors.values) {
            final first = value is List && value.isNotEmpty ? value.first : value;
            final text = first?.toString().trim();
            if (text != null && text.isNotEmpty) return text;
          }
        }
        if (decoded['message'] != null) {
          return decoded['message'].toString();
        }
      }
    } catch (_) {}
    return null;
  }

  /// Bag size (kg per bag) and unit id for every approved product.
  ///
  /// The booking form's *Add Items* section is entered in **bags**, but
  /// `POST /api/booking-person-books` stores whatever `details[].qty` holds as
  /// **kg**, and every downstream report divides by the product's bag size to
  /// turn kg back into bags. So the app has to know kg-per-bag to convert, and
  /// this is where it comes from.
  ///
  /// Source: `GET /api/v2/getChildCateProList`
  /// (`ProductController::getChildCateProductApproveList`). One call, no
  /// parameters, same host and JWT as the booking endpoints — chosen over the
  /// per-product `GET /api/v2/products/{id}` because that would cost a round
  /// trip per selection.
  ///
  /// **A missing entry is normal, not an error.** Products with no
  /// `sizeOrWeight` on file simply stay bag-unaware, and their quantity falls
  /// back to being read as kg — see [BookingFormProductPrice.bagsToKg].
  Future<ApiResult<SalesProductCatalog>> fetchProductCatalog({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedProductCatalog != null) {
      return ApiResult.ok(_cachedProductCatalog!);
    }

    if (useDemoData) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      _cachedProductCatalog = const SalesProductCatalog.byProductId({
        1: SalesProductEntry(sizeOrWeight: 25, unitId: 1),
      });
      return ApiResult.ok(_cachedProductCatalog!);
    }

    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      return ApiResult.fail('Please login to continue.');
    }

    final base = await _salesApiBase();
    final uri = Uri.parse('$base/api/v2/getChildCateProList');

    try {
      final response = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
              'User-Agent': 'PPHLAttendance/2.2 (Android; Flutter)',
            },
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ApiResult.fail(
          'Could not load product bag sizes (${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body);
      final data = decoded is Map<String, dynamic> ? decoded['data'] : null;
      if (data is! List) {
        return ApiResult.fail('Invalid product catalog response.');
      }

      _cachedProductCatalog = SalesProductCatalog.fromApiList(data);
      return ApiResult.ok(_cachedProductCatalog!);
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }
  }

  /// The logged-in officer's Sales `users.id` — the value the feed booking
  /// endpoint wants for `bookingPerson`.
  ///
  /// The HRM employee id the app holds lives in the Sales `users.employeeId`
  /// column, **not** `users.id`, so sending it straight to
  /// `POST /api/booking-person-books` fails the backend's `exists:users,id`
  /// rule with a 422 "Validation failed." (Chicks needs
  /// `sales_employees_flat.id` instead, which `payment-setup-data` already
  /// gives us — this is feed only.)
  ///
  /// Source: `GET /api/v2/user/list?employeeId=` (`UserController::allUser`,
  /// filters `users.employeeId`), falling back to `GET /api/v2/get-my-info`
  /// (`UserController::getSelf`). Both sit under `jwt.verify` — the same group
  /// as the product catalog the app already calls — so the existing token works.
  Future<ApiResult<int>> fetchMySalesUserId(int? canonicalEmployeeId) async {
    if (_cachedSalesUserId != null) {
      return ApiResult.ok(_cachedSalesUserId!);
    }

    if (useDemoData) {
      final demo = (canonicalEmployeeId != null && canonicalEmployeeId > 0)
          ? canonicalEmployeeId
          : 1;
      _cachedSalesUserId = demo;
      return ApiResult.ok(demo);
    }

    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      return ApiResult.fail('Please login to continue.');
    }

    final base = await _salesApiBase();
    final headers = {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      'User-Agent': 'PPHLAttendance/2.2 (Android; Flutter)',
    };

    try {
      if (canonicalEmployeeId != null && canonicalEmployeeId > 0) {
        final uri = Uri.parse(
          '$base/api/v2/user/list?employeeId=$canonicalEmployeeId',
        );
        final response = await http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 30));
        final id = salesUserIdFromList(response.body);
        if (id != null && id > 0) {
          _cachedSalesUserId = id;
          return ApiResult.ok(id);
        }
      }

      final meResponse = await http
          .get(Uri.parse('$base/api/v2/get-my-info'), headers: headers)
          .timeout(const Duration(seconds: 30));
      final id = salesUserIdFromMe(meResponse.body);
      if (id != null && id > 0) {
        _cachedSalesUserId = id;
        return ApiResult.ok(id);
      }
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }

    return ApiResult.fail(
      'Your sales account isn\'t linked. Please contact an admin.',
    );
  }

  /// `data[].id` from `GET /api/v2/user/list` — the Sales `users.id`.
  static int? salesUserIdFromList(String body) {
    try {
      final decoded = jsonDecode(body);
      final data = decoded is Map ? decoded['data'] : null;
      if (data is List) {
        for (final entry in data) {
          if (entry is Map) {
            final id = _asPositiveInt(entry['id']);
            if (id != null) return id;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// `user.id` from `GET /api/v2/get-my-info` — the Sales `users.id`.
  static int? salesUserIdFromMe(String body) {
    try {
      final decoded = jsonDecode(body);
      final user = decoded is Map ? decoded['user'] : null;
      if (user is Map) {
        return _asPositiveInt(user['id']);
      }
    } catch (_) {}
    return null;
  }

  static int? _asPositiveInt(Object? value) {
    final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
    return (parsed != null && parsed > 0) ? parsed : null;
  }
}

/// One product's bag size and unit, as returned by the product catalog.
class SalesProductEntry {
  const SalesProductEntry({this.sizeOrWeight, this.unitId});

  final double? sizeOrWeight;
  final int? unitId;
}

/// Bag size and unit lookup keyed by `productId`.
///
/// Every getter is null-tolerant: a product absent from the catalog, or present
/// with no `sizeOrWeight`, simply yields nulls and the caller falls back to
/// treating its quantity as kg. That is the same direction as the pre-catalog
/// behaviour, so a catalog outage cannot change what gets recorded.
class SalesProductCatalog {
  const SalesProductCatalog.byProductId(this._byProductId);

  final Map<int, SalesProductEntry> _byProductId;

  int get length => _byProductId.length;

  /// Builds the lookup from the API's `data` array.
  ///
  /// Entries with neither a usable bag size nor a unit are dropped rather than
  /// stored as empty records, so `contains` means "this product has something
  /// to say".
  factory SalesProductCatalog.fromApiList(List<dynamic> rows) {
    final byProductId = <int, SalesProductEntry>{};

    for (final row in rows) {
      if (row is! Map) {
        continue;
      }

      final productId = _asInt(row['id'] ?? row['productId']);
      if (productId == null || productId <= 0) {
        continue;
      }

      // `sizeOrWeight` is a decimal with no $casts on the Laravel model, so it
      // arrives as the string "50.00" at least as often as the number 50.
      final sizeOrWeight = _asDouble(row['sizeOrWeight']);
      final unitId = _asInt(row['unitId'] ?? (row['unit'] is Map
          ? (row['unit'] as Map)['id']
          : null));

      if (sizeOrWeight == null && unitId == null) {
        continue;
      }

      byProductId[productId] = SalesProductEntry(
        sizeOrWeight: sizeOrWeight,
        unitId: unitId,
      );
    }

    return SalesProductCatalog.byProductId(Map.unmodifiable(byProductId));
  }

  SalesProductEntry? entryFor(int productId) => _byProductId[productId];

  /// Resolved bag size, or null when the product has none on file.
  double? sizeOrWeightFor(int productId) =>
      _byProductId[productId]?.sizeOrWeight;

  /// Resolved unit id, or null. Callers supply their own default because the
  /// kg unit is a deployment-specific id, not something to hardcode blindly.
  int? unitIdFor(int productId) => _byProductId[productId]?.unitId;

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '');
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    final parsed = double.tryParse(value?.toString().trim() ?? '');
    if (parsed == null || parsed.isNaN || parsed.isInfinite) {
      return null;
    }
    return parsed;
  }
}
