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
import 'fcm_wake_handler.dart';

const String _enabledKey = 'geo_tracking_enabled';
const String _lastPingKey = 'geo_last_ping_json';
const String _queueKey = 'geo_ping_queue';
const String _lastCaptureKey = 'geo_last_capture_ms';

class GeoTrackingService {
  GeoTrackingService({AuthService? authService})
      : _authService = authService ?? AuthService();

  final AuthService _authService;
  static Timer? _foregroundTimer;

  static Future<void> initialize() async {
    FcmWakeHandler.register();
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_enabledKey) ?? false;
    if (enabled) {
      _startForegroundTimer();
    }
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);

    if (enabled) {
      _startForegroundTimer();
      await captureAndQueue();
    } else {
      _foregroundTimer?.cancel();
      _foregroundTimer = null;
    }
  }

  static void _startForegroundTimer() {
    _foregroundTimer?.cancel();
    _foregroundTimer = Timer.periodic(
      Duration(minutes: AppConfig.geoTrackingIntervalMinutes),
      (_) => GeoTrackingService().captureAndQueue(),
    );
  }

  Future<PermissionStatus> requestPermissions() async {
    var status = await Permission.locationWhenInUse.request();
    if (status.isGranted) {
      status = await Permission.locationAlways.request();
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

  Future<void> captureAndQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_lastCaptureKey) ?? 0;
    final elapsed = DateTime.now().millisecondsSinceEpoch - lastMs;
    final minIntervalMs = AppConfig.geoTrackingIntervalMinutes * 60 * 1000;
    if (elapsed < minIntervalMs && lastMs > 0) return;

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

      await _tryUpload(ping);
    } catch (error) {
      debugPrint('Geo capture failed: $error');
    }
  }

  Future<void> _tryUpload(GeoPing ping) async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) return;

    try {
      final response = await http
          .post(
            Uri.parse(AppConfig.geoLocationUploadUrl),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
              'User-Agent': 'PPHLAttendance/2.0 (Android; Flutter)',
            },
            body: jsonEncode({
              'lat': ping.latitude,
              'lng': ping.longitude,
              'address': ping.address,
              'capturedAt': ping.capturedAt.toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _markUploaded(ping);
      }
    } catch (_) {
      // Keep queued — backend endpoint not ready yet.
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
