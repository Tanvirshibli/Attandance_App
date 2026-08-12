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

  String? _messageFromBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] != null) {
        return decoded['message'].toString();
      }
    } catch (_) {}
    return null;
  }
}
