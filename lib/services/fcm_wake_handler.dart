import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'endpoint_config_service.dart';
import 'geo_tracking_service.dart';

/// Scaffold for Firebase Cloud Messaging geo wake-up.
///
/// ## Enable later
/// 1. Create a Firebase project and add Android app with package
///    `com.pphl.employee_attendance`.
/// 2. Download `google-services.json` into `android/app/`.
/// 3. Add `firebase_core` + `firebase_messaging` to `pubspec.yaml` and apply
///    the Google Services Gradle plugin.
/// 4. Wire [register] to `FirebaseMessaging.onMessage` /
///    `onBackgroundMessage` and call [onWakeRequested] from data pushes.
/// 5. After obtaining a device token, call [registerTokenWithBackend].
///
/// Until then this class is a safe no-op so release builds compile without
/// Firebase credentials.
class FcmWakeHandler {
  static const bool isConfigured = false;

  static String get statusLabel =>
      isConfigured ? 'FCM: configured' : 'FCM: not configured (scaffold)';

  static void register() {
    // No firebase_messaging dependency in this build.
    debugPrint(
      'FcmWakeHandler: scaffold only — add google-services.json to enable.',
    );
  }

  /// Called when an FCM data message requests a geo capture.
  static Future<void> onWakeRequested() async {
    if (!isConfigured) return;
    await GeoTrackingService().captureAndQueue(source: 'fcm_wake');
  }

  /// POST token to ZKTeco `geo.fcm_token` (`/api/v1/mobile/fcm-token`).
  /// Only runs when [fcmToken] is non-empty (never in scaffold builds).
  static Future<bool> registerTokenWithBackend({
    required int employeeId,
    required String fcmToken,
  }) async {
    if (!isConfigured || fcmToken.trim().isEmpty || employeeId <= 0) {
      return false;
    }

    return _postFcmToken(employeeId: employeeId, fcmToken: fcmToken.trim());
  }

  /// Shared helper for the real Firebase integration path.
  static Future<bool> _postFcmToken({
    required int employeeId,
    required String fcmToken,
  }) async {
    final config = EndpointConfigService.instance;
    final url = await config.resolveUrl('geo.fcm_token') ??
        '${AppConfig.attendanceApiBaseUrl}/api/v1/mobile/fcm-token';

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'User-Agent': 'PPHLAttendance/2.1 (Android; Flutter)',
            },
            body: jsonEncode({
              'employee_id': employeeId,
              'fcm_token': fcmToken,
            }),
          )
          .timeout(const Duration(seconds: 15));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (error) {
      debugPrint('FCM token register failed: $error');
      return false;
    }
  }
}
