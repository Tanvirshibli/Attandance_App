import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
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
/// [isConfigured] stays false and all methods are safe no-ops.
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

    try {
      await Permission.notification.request();
    } catch (_) {}

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
  static Future<void> onWakeRequested() async {
    if (!isConfigured) return;
    await GeoTrackingService().captureAndQueue(source: 'fcm_wake');
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
