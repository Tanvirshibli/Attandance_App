import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'auth_service.dart';
import 'device_identity_service.dart';
import 'endpoint_config_service.dart';
import 'geo_tracking_service.dart';

/// Top-level background handler (must be a top-level or static function).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Already initialized or missing google-services.json.
  }
  await FcmWakeHandler.handleRemoteMessage(message);
}

/// Firebase Cloud Messaging geo wake-up.
///
/// Requires `android/app/google-services.json` (see `.example`). Without it,
/// [isConfigured] stays false on the UI isolate and the token-registration
/// methods are safe no-ops. The background handler (see
/// [firebaseMessagingBackgroundHandler]) no longer depends on that per-isolate
/// static — [register] only ever runs on the UI isolate, so the background
/// isolate checks `Firebase.apps` and SharedPreferences directly.
class FcmWakeHandler {
  static bool _configured = false;
  static bool _listenersBound = false;

  static bool get isConfigured => _configured;

  static String get statusLabel =>
      isConfigured ? 'FCM: configured' : 'FCM: not configured';

  /// Initialize Firebase + messaging listeners. Safe if credentials missing.
  static Future<void> register() async {
    if (_listenersBound) return;

    try {
      await Firebase.initializeApp();
      _configured = true;
    } catch (error) {
      _configured = false;
      debugPrint(
        'FcmWakeHandler: Firebase init failed (add google-services.json): $error',
      );
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;
    await messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );

    FirebaseMessaging.onMessage.listen(handleRemoteMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(handleRemoteMessage);

    messaging.onTokenRefresh.listen((token) {
      syncTokenWithBackend(fcmToken: token);
    });

    _listenersBound = true;

    final token = await messaging.getToken();
    if (token != null && token.isNotEmpty) {
      await syncTokenWithBackend(fcmToken: token);
    }
  }

  static Future<void> handleRemoteMessage(RemoteMessage message) async {
    final data = message.data;
    final type = (data['type'] ?? data['action'] ?? '').toString().trim();
    if (type != 'geo_wake') return;
    await onWakeRequested();
  }

  /// Called when an FCM data message requests a geo capture.
  ///
  /// Runs in whichever isolate received the push. The UI-isolate-only
  /// [_configured] static cannot be trusted here (it is false in the background
  /// isolate), so the gate is rebuilt from `Firebase.apps` and the same
  /// SharedPreferences the WorkManager worker reads. The capture then drains
  /// the queue, which the wake path previously never did.
  static Future<void> onWakeRequested() async {
    if (Firebase.apps.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final trackingEnabled = prefs.getBool('geo_tracking_enabled') ?? false;
    if (!trackingEnabled) return;

    final pausedUntil = prefs.getInt('geo_hrm_paused_until_ms') ?? 0;
    if (!wakeRequestAllowed(
      firebaseConfigured: Firebase.apps.isNotEmpty,
      trackingEnabled: trackingEnabled,
      pausedUntilMs: pausedUntil,
      now: DateTime.now(),
    )) {
      return;
    }

    final service = GeoTrackingService();
    await service.captureAndQueue(source: 'fcm_wake');
    await service.flushQueue();
  }

  /// The gate [onWakeRequested] evaluates before capturing, split out so the
  /// truth table is testable without Firebase or SharedPreferences.
  ///
  /// [firebaseConfigured] is `Firebase.apps` being non-empty rather than
  /// [isConfigured]: the background isolate never runs [register], so the
  /// per-isolate static would always deny there.
  @visibleForTesting
  static bool wakeRequestAllowed({
    required bool firebaseConfigured,
    required bool trackingEnabled,
    required int pausedUntilMs,
    required DateTime now,
  }) {
    return firebaseConfigured &&
        trackingEnabled &&
        now.millisecondsSinceEpoch >= pausedUntilMs;
  }

  /// Refresh token registration using current geo-enabled preference.
  static Future<bool> syncTokenWithBackend({String? fcmToken}) async {
    if (!isConfigured) return false;

    final token = (fcmToken ?? await FirebaseMessaging.instance.getToken())
        ?.trim();
    if (token == null || token.isEmpty) return false;

    final profile = await AuthService().getCurrentUserProfile();
    final employeeId = profile?.canonicalEmployeeId;
    if (employeeId == null || employeeId <= 0) return false;

    final prefs = await SharedPreferences.getInstance();
    final geoEnabled = prefs.getBool('geo_tracking_enabled') ?? false;

    return registerTokenWithBackend(
      employeeId: employeeId,
      fcmToken: token,
      geoTrackingEnabled: geoEnabled,
    );
  }

  /// POST token to ZKTeco `geo.fcm_token` (`/api/v1/mobile/fcm-token`).
  static Future<bool> registerTokenWithBackend({
    required int employeeId,
    required String fcmToken,
    bool? geoTrackingEnabled,
  }) async {
    if (!isConfigured || fcmToken.trim().isEmpty || employeeId <= 0) {
      return false;
    }

    String? deviceId;
    try {
      final meta = await DeviceIdentityService().getDeviceMetadata();
      deviceId = meta['deviceIdentifier'];
    } catch (_) {}

    bool enabled = geoTrackingEnabled ?? false;
    if (geoTrackingEnabled == null) {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool('geo_tracking_enabled') ?? false;
    }

    return _postFcmToken(
      employeeId: employeeId,
      fcmToken: fcmToken.trim(),
      deviceId: deviceId,
      geoTrackingEnabled: enabled,
    );
  }

  /// Best-effort token deregistration on logout.
  ///
  /// Marks the device's token as geo-disabled on the backend so a signed-out
  /// handset stops being woken for captures. The whole body is wrapped because
  /// logout must complete even when Firebase or the network is unavailable:
  /// failures are logged and swallowed, never rethrown.
  static Future<void> deregisterForLogout({required int employeeId}) async {
    try {
      if (!isConfigured || employeeId <= 0) return;

      final token = (await FirebaseMessaging.instance.getToken())?.trim();
      if (token == null || token.isEmpty) return;

      await registerTokenWithBackend(
        employeeId: employeeId,
        fcmToken: token,
        geoTrackingEnabled: false,
      );
    } catch (error) {
      debugPrint('FCM deregister failed: $error');
    }
  }

  static Future<bool> _postFcmToken({
    required int employeeId,
    required String fcmToken,
    String? deviceId,
    required bool geoTrackingEnabled,
  }) async {
    final config = EndpointConfigService.instance;
    final url = await config.resolveUrl('geo.fcm_token') ??
        '${AppConfig.attendanceApiBaseUrl}/api/v1/mobile/fcm-token';

    try {
      final body = <String, dynamic>{
        'employee_id': employeeId,
        'fcm_token': fcmToken,
        'geo_tracking_enabled': geoTrackingEnabled,
      };
      if (deviceId != null && deviceId.isNotEmpty) {
        body['device_id'] = deviceId;
      }

      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'User-Agent': 'PPHLAttendance/2.1 (Android; Flutter)',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (error) {
      debugPrint('FCM token register failed: $error');
      return false;
    }
  }
}
