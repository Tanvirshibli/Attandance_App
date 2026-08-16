import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/api_result.dart';
import '../models/vehicle_models.dart';
import 'endpoint_config_service.dart';

class VehicleService {
  VehicleService({EndpointConfigService? configService})
      : _configService = configService ?? EndpointConfigService.instance;

  final EndpointConfigService _configService;

  Future<bool> isVehicleEnabled() =>
      _configService.isFeatureEnabled('vehicle.enabled', defaultValue: true);

  Future<ApiResult<List<VehicleSummary>>> getActiveVehicles() async {
    if (!await isVehicleEnabled()) {
      return ApiResult.fail('feature_disabled');
    }

    final url = (await _configService.resolveUrl('vehicle.list')) ??
        '${AppConfig.transportApiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/api/get-vehicle-active-list';

    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'PPHLAttendance/2.2 (Android; Flutter)',
            },
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ApiResult.fail(
          'Could not load vehicles (${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return ApiResult.fail('Invalid vehicles response.');
      }
      final map = Map<String, dynamic>.from(decoded);
      if (map['success'] == false) {
        return ApiResult.fail(
          map['message']?.toString() ?? 'Could not load vehicles.',
        );
      }

      final data = map['data'];
      if (data is! List) {
        return ApiResult.fail('Invalid vehicles payload.');
      }

      final vehicles = data
          .whereType<Map>()
          .map((e) => VehicleSummary.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      return ApiResult.ok(vehicles);
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }
  }

  Future<ApiResult<VehicleMaintenanceHistory>> getMaintenanceHistory(
    int vehicleId,
  ) async {
    if (!await isVehicleEnabled()) {
      return ApiResult.fail('feature_disabled');
    }

    if (vehicleId <= 0) {
      return ApiResult.fail('Invalid vehicle.');
    }

    final base = (await _configService.resolveUrl('vehicle.maintenance')) ??
        '${AppConfig.transportApiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/api/get-vehicle-m-history';

    try {
      final response = await http
          .get(
            Uri.parse('$base/$vehicleId'),
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'PPHLAttendance/2.2 (Android; Flutter)',
            },
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ApiResult.fail(
          'Could not load maintenance (${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return ApiResult.fail('Invalid maintenance response.');
      }
      final map = Map<String, dynamic>.from(decoded);
      if (map['success'] == false) {
        return ApiResult.fail(
          map['message']?.toString() ?? 'Could not load maintenance.',
        );
      }

      return ApiResult.ok(VehicleMaintenanceHistory.fromJson(map));
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }
  }

  Future<ApiResult<TripListPage>> getTrips({
    int page = 1,
    int? vehicleId,
  }) async {
    if (!await isVehicleEnabled()) {
      return ApiResult.fail('feature_disabled');
    }

    final base = (await _configService.resolveUrl('vehicle.trips')) ??
        '${AppConfig.transportApiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/api/get-trips-list';

    final params = <String, String>{'page': '$page'};
    if (vehicleId != null && vehicleId > 0) {
      params['vehicle_id'] = '$vehicleId';
    }

    final uri = Uri.parse(base).replace(queryParameters: params);

    try {
      final response = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'PPHLAttendance/2.2 (Android; Flutter)',
            },
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ApiResult.fail(
          'Could not load trips (${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return ApiResult.fail('Invalid trips response.');
      }
      final map = Map<String, dynamic>.from(decoded);
      if (map['success'] == false) {
        return ApiResult.fail(
          map['message']?.toString() ?? 'Could not load trips.',
        );
      }

      var pageData = TripListPage.fromJson(map);
      if (vehicleId != null && vehicleId > 0) {
        pageData = TripListPage(
          trips: pageData.trips
              .where((t) => t.involvesVehicle(vehicleId))
              .toList(),
          currentPage: pageData.currentPage,
          lastPage: pageData.lastPage,
          total: pageData.total,
          message: pageData.message,
          statusCounts: pageData.statusCounts,
        );
      }
      return ApiResult.ok(pageData);
    } catch (error) {
      return ApiResult.fail('Network error: $error');
    }
  }
}
