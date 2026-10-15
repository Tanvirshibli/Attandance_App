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
import 'device_identity_service.dart';
import 'endpoint_config_service.dart';
import 'fcm_wake_handler.dart';
import 'geo_background_worker.dart';
import 'geo_notification_service.dart';
import 'permission_service.dart';

const String _enabledKey = 'geo_tracking_enabled';
const String _lastPingKey = 'geo_last_ping_json';
const String _queueKey = 'geo_ping_queue';
const String _lastCaptureKey = 'geo_last_capture_ms';
const String _hrmPausedUntilKey = 'geo_hrm_paused_until_ms';
const String _employeeIdKey = 'canonical_employee_id';

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

  /// Stop foreground/background HRM-bound geo work so leftover traffic cannot
  /// block the next login on the same IP after 429 or logout, and drop the
  /// session-scoped geo state (employee id, pending queue, last ping).
  Future<void> pauseForLogout() async {
    _foregroundTimer?.cancel();
    _foregroundTimer = null;
    await GeoBackgroundWorker.cancelPeriodicTask();
    await GeoNotificationService.instance.cancelTrackingNotification();
    // The persisted employee id belongs to the session that just ended; a
    // background isolate must not upload the next user's pings under it.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_employeeIdKey);
    // Pending pings and the last-ping mirror are session-scoped too: once this
    // session's token and geo registration are gone, a later flush would post
    // them under the next user's employee id.
    await prefs.remove(_queueKey);
    await prefs.remove(_lastPingKey);
    await prefs.remove(_lastCaptureKey);
    await _setHrmPausedUntil(
      DateTime.now().add(const Duration(minutes: 2)),
    );
  }

  Future<void> pauseForRateLimit({Duration duration = const Duration(minutes: 1)}) async {
    await _setHrmPausedUntil(DateTime.now().add(duration));
    debugPrint('Geo HRM calls paused for ${duration.inSeconds}s due to rate limit');
  }

  Future<void> clearHrmPause() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hrmPausedUntilKey);
  }

  Future<bool> _isHrmPaused() async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(_hrmPausedUntilKey) ?? 0;
    return DateTime.now().millisecondsSinceEpoch < until;
  }

  Future<void> _setHrmPausedUntil(DateTime until) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_hrmPausedUntilKey, until.millisecondsSinceEpoch);
  }

  /// Resolves the employee id for uploads: in-memory cache, then the persisted
  /// mirror, then the network.
  ///
  /// Order matters for background isolates. They start with an empty
  /// [AuthService] — no in-memory profile — so the persisted
  /// `canonical_employee_id` preference is what lets a 15-minute worker or an
  /// FCM wake-up finish an upload without a slow, failure-prone profile fetch.
  /// When nothing is persisted (or [forceRefresh] demands fresh data) it falls
  /// back to the network as before.
  Future<int?> _resolveEmployeeId({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = _authService.cachedCanonicalEmployeeId;
      if (cached != null && cached > 0) {
        return cached;
      }
      final prefs = await SharedPreferences.getInstance();
      final persisted = prefs.getInt(_employeeIdKey);
      if (persisted != null && persisted > 0) {
        return persisted;
      }
    }
    final profile =
        await _authService.getCurrentUserProfile(forceRefresh: forceRefresh);
    return profile?.canonicalEmployeeId;
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  /// Geo tracking is reachable when the deployment enables the feature **and**
  /// the signed-in user holds `tracking.read`.
  ///
  /// The flag is deployment-wide; the permission is per-user. Gating here rather
  /// than only on the Geo Tracking screen matters because
  /// [ensureEnabledIfAllowed] runs at bootstrap and on resume — without the
  /// permission check here, a user who may not see the module would still have
  /// the app silently uploading their location in the background.
  ///
  /// This runs in fresh background isolates too (the WorkManager dispatcher and
  /// the FCM background handler), where [PermissionService] was never fed by a
  /// profile fetch — without hydration the gate would deny every background
  /// capture for every user. Hydrating restores the grants the UI isolate last
  /// persisted; when no snapshot exists the service stays unloaded and the gate
  /// still fails closed, so a device that never signed in captures nothing.
  Future<bool> isGeoFeatureEnabled() async {
    if (!PermissionService.instance.isLoaded) {
      await PermissionService.instance.hydrateFromStorage();
    }
    final enabled = await _configService.isFeatureEnabled(
      'geo.tracking.enabled',
      defaultValue: true,
    );
    return enabled &&
        PermissionService.instance.canViewModule('tracking');
  }

  /// Turn tracking on when the feature flag is on and background location is granted.
  /// Safe to call after the permissions gate, on login, or when opening Geo Tracking.
  Future<bool> ensureEnabledIfAllowed() async {
    if (!await isGeoFeatureEnabled()) {
      return false;
    }
    final always = await Permission.locationAlways.status;
    if (!always.isGranted && !always.isLimited) {
      return false;
    }
    await setEnabled(true);
    return true;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);

    if (enabled) {
      await clearHrmPause();
      await _startForegroundTimer();
      await GeoBackgroundWorker.registerPeriodicTask();
      final intervalMinutes = await _configService.geoIntervalMinutes();
      await GeoNotificationService.instance
          .showTrackingActive(intervalMinutes: intervalMinutes);
      await FcmWakeHandler.syncTokenWithBackend();
      await captureAndQueue(source: 'manual');
    } else {
      _foregroundTimer?.cancel();
      _foregroundTimer = null;
      await GeoBackgroundWorker.cancelPeriodicTask();
      await GeoNotificationService.instance.cancelTrackingNotification();
      await FcmWakeHandler.syncTokenWithBackend();
    }
  }

  Future<int> configuredIntervalMinutes() =>
      _configService.geoIntervalMinutes();

  /// Recent pings from ZKTeco `geo.history` (falls back to local queue).
  Future<List<GeoPing>> fetchHistory({int limit = 20}) async {
    final employeeId = await _resolveEmployeeId();
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

    // Background wake-ups run on borrowed time (a WorkManager slot or an FCM
    // data push), so a fix that misses the window is worth less than an older
    // one: give it 45s, then fall back to the last known position. Foreground
    // captures keep the interactive 20s limit.
    final backgroundSource = source == 'background' || source == 'fcm_wake';

    Position? position;
    var fromLastKnown = false;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: backgroundSource ? 45 : 20),
        ),
      );
    } catch (error) {
      debugPrint('Geo capture failed: $error');
      if (!backgroundSource) {
        return;
      }
      debugPrint('Geo $source capture: falling back to last known position');
      try {
        position = await Geolocator.getLastKnownPosition();
        fromLastKnown = position != null;
      } catch (fallbackError) {
        debugPrint('Geo last-known fallback failed: $fallbackError');
      }
    }

    if (position == null) {
      debugPrint('Geo capture abandoned ($source): no position available');
      return;
    }

    try {
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

      // The fix and the address can take up to 45 s. A logout landing in that
      // window removes the session's queue and last-ping mirror; persisting
      // now would re-create them, and a later flush would post this
      // observation under the next user's employee id. Re-check the session
      // before writing anything.
      if (await _authService.getToken() == null) {
        return;
      }
      if (!await isGeoFeatureEnabled()) {
        return;
      }

      final ping = GeoPing(
        latitude: position.latitude,
        longitude: position.longitude,
        // A last-known fix can be minutes old; label it with its own timestamp
        // instead of "now", which would misreport a stale location as fresh.
        capturedAt: fromLastKnown ? position.timestamp : DateTime.now(),
        address: address,
        accuracyM: position.accuracy,
      );

      await prefs.setString(_lastPingKey, jsonEncode(ping.toJson()));
      await prefs.setInt(_lastCaptureKey, DateTime.now().millisecondsSinceEpoch);

      final queue = await _loadQueue();
      // Two background captures can reuse the same last-known fix, producing an
      // identical observation (same capture time and coordinates). Coalescing
      // keeps queue entries unique, so an upload can only ever mark its own
      // entry — and the duplicate is not posted a second time.
      final duplicate = queue.any(
        (item) =>
            item.capturedAt == ping.capturedAt &&
            item.latitude == ping.latitude &&
            item.longitude == ping.longitude,
      );
      if (duplicate) {
        return;
      }

      queue.add(ping);
      await _saveQueue(queue);

      await _tryUpload(ping, source: source);
    } catch (error) {
      debugPrint('Geo capture failed: $error');
    }
  }

  Future<void> _tryUpload(
    GeoPing ping, {
    String source = 'foreground',
    int? employeeId,
  }) async {
    if (await _isHrmPaused()) {
      return;
    }

    final resolvedId = employeeId ?? await _resolveEmployeeId();
    if (resolvedId == null || resolvedId <= 0) return;

    final uploadUrl = await _configService.resolveUrl('geo.upload') ??
        AppConfig.geoLocationUploadUrl;

    try {
      String? deviceId;
      try {
        final meta = await DeviceIdentityService().getDeviceMetadata();
        deviceId = meta['deviceIdentifier'];
      } catch (_) {}

      final body = <String, dynamic>{
        'employee_id': resolvedId,
        'lat': ping.latitude,
        'lng': ping.longitude,
        'address': ping.address,
        'accuracy_m': ping.accuracyM,
        'captured_at': ping.capturedAt.toIso8601String(),
        'source': source,
      };
      if (deviceId != null && deviceId.isNotEmpty) {
        body['device_id'] = deviceId;
      }

      final response = await http
          .post(
            Uri.parse(uploadUrl),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'User-Agent': 'PPHLAttendance/2.1 (Android; Flutter)',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 429) {
        final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
        await pauseForRateLimit(
          duration: Duration(seconds: retryAfter != null && retryAfter > 0 ? retryAfter : 60),
        );
        return;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _markUploaded(ping);
      }
    } catch (_) {
      // Keep queued for retry.
    }
  }

  Future<void> flushQueue() async {
    if (await _isHrmPaused()) {
      return;
    }

    final queue = await _loadQueue();
    final pending = queue.where((p) => !p.uploaded).toList();
    if (pending.isEmpty) {
      return;
    }

    // Resolve profile once per flush batch (avoids N× get-my-info).
    final employeeId = await _resolveEmployeeId();
    if (employeeId == null || employeeId <= 0) {
      return;
    }

    for (final ping in pending) {
      if (await _isHrmPaused()) {
        break;
      }
      await _tryUpload(ping, source: 'background', employeeId: employeeId);
    }
  }

  /// Marks the queued copy of [ping] as uploaded.
  ///
  /// Matches on capture time **and** coordinates and marks a single entry, so a
  /// duplicate observation — which [captureAndQueue] coalesces — can never
  /// cause a sibling's upload bookkeeping to be applied to the wrong entry.
  Future<void> _markUploaded(GeoPing ping) async {
    final queue = await _loadQueue();
    var marked = false;
    final updated = <GeoPing>[];
    for (final item in queue) {
      if (!marked &&
          !item.uploaded &&
          item.capturedAt == ping.capturedAt &&
          item.latitude == ping.latitude &&
          item.longitude == ping.longitude) {
        marked = true;
        updated.add(
          GeoPing(
            latitude: item.latitude,
            longitude: item.longitude,
            capturedAt: item.capturedAt,
            address: item.address,
            accuracyM: item.accuracyM,
            uploaded: true,
          ),
        );
        continue;
      }
      updated.add(item);
    }
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
