import 'package:employee_attendance/models/endpoint_config.dart';
import 'package:employee_attendance/models/sales_booking_post_models.dart';
import 'package:employee_attendance/services/endpoint_config_service.dart';
import 'package:employee_attendance/services/sales_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers feature flags from a fixed map and records every endpoint
/// resolve, so a test can prove the gate rejected a request *before*
/// any network call was attempted.
class _FakeEndpointConfigService implements EndpointConfigService {
  _FakeEndpointConfigService(this.features);

  final Map<String, dynamic> features;
  final List<String> resolveUrlCalls = [];

  @override
  Future<bool> isFeatureEnabled(String key,
      {bool defaultValue = false}) async {
    return features[key] as bool? ?? defaultValue;
  }

  @override
  Future<String?> resolveUrl(String key) async {
    resolveUrlCalls.add(key);
    return 'https://sales.invalid/api/booking-person-books';
  }

  // Nothing below is reached on the gated path.
  @override
  Future<bool> hasBootstrapUrl() async => false;

  @override
  Future<String?> getBootstrapBaseUrl() async => null;

  @override
  Future<void> setBootstrapBaseUrl(String baseUrl) async {}

  @override
  Future<EndpointConfig?> getConfig({bool forceRefresh = false}) async =>
      null;

  @override
  Future<EndpointConfig?> refreshConfig() async => null;

  @override
  Future<List<String>> resolveUrlCandidates(String key) async => const [];

  @override
  Future<int> geoIntervalMinutes() async => 0;

  @override
  Future<String?> hrmBaseUrl() async => null;

  @override
  Future<String?> zktecoBaseUrl() async => null;
}

CreateBookingPersonBookRequest _request(String module) {
  return CreateBookingPersonBookRequest(
    module: module,
    dealerId: 1,
    categoryId: 1,
    subCategoryId: 1,
    childCategoryId: 1,
    bookingPointId: 1,
    bookingType: 'regular',
    isBookingMoney: false,
    isMultiDelivery: false,
    discount: 0,
    discountType: 'percent',
    advanceAmount: 0,
    totalAmount: 0,
    bookingDate: '2026-01-01',
    invoiceDate: '2026-01-01',
    lines: const [],
  );
}

void main() {
  test('chick booking is rejected before any network call while disabled',
      () async {
    final config = _FakeEndpointConfigService({'sales.enabled': true});
    final service = SalesService(configService: config);

    final result = await service.createBookingPersonBook(_request('chicks'));

    expect(result.success, isFalse);
    expect(result.message, 'Chick booking is temporarily disabled.');
    expect(config.resolveUrlCalls, isEmpty);
  });

  test('isChicksBookingEnabled fails closed without the key', () async {
    final config = _FakeEndpointConfigService({'sales.enabled': true});
    final service = SalesService(configService: config);

    expect(await service.isChicksBookingEnabled(), isFalse);
  });

  test('feed booking passes the gate and reaches the endpoint resolve',
      () async {
    final config = _FakeEndpointConfigService({'sales.enabled': true});
    final service = SalesService(configService: config);

    final result = await service.createBookingPersonBook(_request('feed'));

    expect(config.resolveUrlCalls, ['sales.booking.create']);
    // The fake host is unreachable, so the call fails — but it must
    // have passed the gate first.
    expect(result.success, isFalse);
    expect(result.message, isNot('Chick booking is temporarily disabled.'));
  });

  test('chick booking passes the gate once the flag is on', () async {
    final config = _FakeEndpointConfigService({
      'sales.enabled': true,
      'sales.chicksBooking.enabled': true,
    });
    final service = SalesService(configService: config);

    final result = await service.createBookingPersonBook(_request('chicks'));

    expect(config.resolveUrlCalls, ['sales.booking.create']);
    expect(result.success, isFalse);
    expect(result.message, isNot('Chick booking is temporarily disabled.'));
  });
}
