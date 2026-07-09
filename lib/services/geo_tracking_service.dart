import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/geo_ping.dart';
import 'auth_service.dart';
import 'endpoint_config_service.dart';
import 'fcm_wake_handler.dart';
import 'geo_background_worker.dart';
import 'geo_notification_service.dart';

const String _enabledKey = 'geo_tracking_enabled';
const String _lastPingKey = 'geo_last_ping_json';
const String _queueKey = 'geo_ping_queue';
const String _lastCaptureKey = 'geo_last_capture_ms';

class GeoTrackingService {
  GeoTrackingService({
    AuthService? authService,
    EndpointConfigService? configService,
  })  : _authService = authService ?? AuthService(),
        _configService = configService ?? EndpointConfigService.instance;

  final AuthService _authService;
  final EndpointConfigService _configService;
  static Timer? _foregroundTimer;

  static Future<void> initialize() async {
    FcmWakeHandler.register();
    await GeoNotificationService.instance.initialize();
    await GeoBackgroundWorker.initialize();
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_enabledKey) ?? false;
    if (enabled) {
      await _startForegroundTimer();
      final interval = await GeoTrackingService()._configService.geoIntervalMinutes();
      await GeoNotificationService.instance
          .showTrackingActive(intervalMinutes: interval);
    }
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  Future<bool> isGeoFeatureEnabled() =>
      _configService.isFeatureEnabled('geo.tracking.enabled', defaultValue: true);

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);

    if (enabled) {
      await _startForegroundTimer();
      await GeoBackgroundWorker.registerPeriodicTask();
      final intervalMinutes = await _configService.geoIntervalMinutes();
      await GeoNotificationService.instance
          .showTrackingActive(intervalMinutes: intervalMinutes);
      await captureAndQueue(source: 'manual');
    } else {
      _foregroundTimer?.cancel();
      _foregroundTimer = null;
      await GeoBackgroundWorker.cancelPeriodicTask();
      await GeoNotificationService.instance.cancelTrackingNotification();
    }
  }

  Future<int> configuredIntervalMinutes() =>
      _configService.geoIntervalMinutes();

  /// Recent pings from ZKTeco `geo.history` (falls back to local queue).
  Future<List<GeoPing>> fetchHistory({int limit = 20}) async {
    final profile = await _authService.getCurrentUserProfile();
    final employeeId = profile?.canonicalEmployeeId;
    if (employeeId == null || employeeId <= 0) {
      final queue = await _loadQueue();
      return queue.reversed.take(limit).toList();
    }

    final historyUrl = await _configService.resolveUrl('geo.history') ??
        '${AppConfig.attendanceApiBaseUrl}/api/v1/mobile/geo-location';

    try {
      final uri = Uri.parse(historyUrl).replace(queryParameters: {
        'employee_id': '$employeeId',
        'limit': '$limit',
      });
      final response = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'PPHLAttendance/2.1 (Android; Flutter)',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final records = decoded['records'];
          if (records is List) {
            return records
                .whereType<Map>()
                .map((row) => GeoPing.fromServerJson(
                      Map<String, dynamic>.from(row),
                    ))
                .toList();
          }
        }
      }
    } catch (error) {
      debugPrint('Geo history fetch failed: $error');
    }

    final queue = await _loadQueue();
    return queue.reversed.take(limit).toList();
  }

  static Future<void> _startForegroundTimer() async {
    final service = GeoTrackingService();
    final intervalMinutes = await service._configService.geoIntervalMinutes();

    _foregroundTimer?.cancel();
    _foregroundTimer = Timer.periodic(
      Duration(minutes: intervalMinutes),
      (_) => GeoTrackingService().captureAndQueue(source: 'foreground'),
    );
  }

  Future<PermissionStatus> requestPermissions() async {
    var status = await Permission.locationWhenInUse.request();
    if (status.isGranted) {
      status = await Permission.locationAlways.request();
    }
    if (status.isGranted) {
      await Permission.notification.request();
    }
    return status;
  }

  Future<String> permissionSummary() async {
    final whenInUse = await Permission.locationWhenInUse.status;
    final always = await Permission.locationAlways.status;
    if (always.isGranted) return 'Background location granted';
    if (whenInUse.isGranted) return 'Foreground location only';
    return 'Location permission not granted';
  }

  Future<GeoPing?> getLastPing() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastPingKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return GeoPing.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  Future<int> pendingUploadCount() async {
    final queue = await _loadQueue();
    return queue.where((p) => !p.uploaded).length;
  }

  Future<void> captureAndQueue({String source = 'foreground'}) async {
    if (!await isGeoFeatureEnabled()) return;

    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_lastCaptureKey) ?? 0;
    final elapsed = DateTime.now().millisecondsSinceEpoch - lastMs;
    final intervalMinutes = await _configService.geoIntervalMinutes();
    final minIntervalMs = intervalMinutes * 60 * 1000;
    if (elapsed < minIntervalMs && lastMs > 0 && source == 'foreground') {
      return;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );

      String? address;
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          address = [p.street, p.subLocality, p.locality, p.country]
              .where((e) => e != null && e.trim().isNotEmpty)
              .join(', ');
        }
      } catch (_) {}

      final ping = GeoPing(
        latitude: position.latitude,
        longitude: position.longitude,
        capturedAt: DateTime.now(),
        address: address,
      );

      await prefs.setString(_lastPingKey, jsonEncode(ping.toJson()));
      await prefs.setInt(_lastCaptureKey, DateTime.now().millisecondsSinceEpoch);

      final queue = await _loadQueue();
      queue.add(ping);
      await _saveQueue(queue);

      await _tryUpload(ping, source: source);
    } catch (error) {
      debugPrint('Geo capture failed: $error');
    }
  }

  Future<void> _tryUpload(GeoPing ping, {String source = 'foreground'}) async {
    final profile = await _authService.getCurrentUserProfile();
    final employeeId = profile?.canonicalEmployeeId;
    if (employeeId == null || employeeId <= 0) return;

    final uploadUrl = await _configService.resolveUrl('geo.upload') ??
        AppConfig.geoLocationUploadUrl;

    try {
      final response = await http
          .post(
            Uri.parse(uploadUrl),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'User-Agent': 'PPHLAttendance/2.1 (Android; Flutter)',
            },
            body: jsonEncode({
              'employee_id': employeeId,
              'lat': ping.latitude,
              'lng': ping.longitude,
              'address': ping.address,
              'accuracy_m': ping.accuracyM,
              'captured_at': ping.capturedAt.toIso8601String(),
              'source': source,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _markUploaded(ping);
      }
    } catch (_) {
      // Keep queued for retry.
    }
  }

  Future<void> flushQueue() async {
    final queue = await _loadQueue();
    for (final ping in queue.where((p) => !p.uploaded)) {
      await _tryUpload(ping, source: 'background');
    }
  }

  Future<void> _markUploaded(GeoPing ping) async {
    final queue = await _loadQueue();
    final updated = queue
        .map(
          (item) => item.capturedAt == ping.capturedAt
              ? GeoPing(
                  latitude: item.latitude,
                  longitude: item.longitude,
                  capturedAt: item.capturedAt,
                  address: item.address,
                  accuracyM: item.accuracyM,
                  uploaded: true,
                )
              : item,
        )
        .toList();
    await _saveQueue(updated);
  }

  Future<List<GeoPing>> _loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(GeoPing.fromJson)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _saveQueue(List<GeoPing> queue) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed =
        queue.length > 200 ? queue.sublist(queue.length - 200) : queue;
    await prefs.setString(
      _queueKey,
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }
}
