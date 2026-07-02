/// Placeholder for Firebase Cloud Messaging wake-up integration.
///
/// When `google-services.json` is added and Firebase is configured,
/// register [FirebaseMessaging.onBackgroundMessage] here to call
/// [GeoTrackingService.captureAndQueue] on data push.
class FcmWakeHandler {
  static void register() {
    // Firebase not configured in this build — no-op until backend team
    // provides FCM project + google-services.json.
  }

  static Future<void> onWakeRequested() async {
    // Called when FCM data message arrives (future).
  }
}
