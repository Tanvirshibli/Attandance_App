import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Ongoing notification while geo tracking is enabled (user-visible FGS-style cue).
class GeoNotificationService {
  GeoNotificationService._();
  static final GeoNotificationService instance = GeoNotificationService._();

  static const int _notificationId = 42001;
  static const String _channelId = 'geo_tracking';
  static const String _channelName = 'Geo Tracking';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Shows when background geo tracking is active',
        importance: Importance.low,
      ),
    );

    _initialized = true;
  }

  Future<void> showTrackingActive({required int intervalMinutes}) async {
    await initialize();

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Shows when background geo tracking is active',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      category: AndroidNotificationCategory.service,
    );

    await _plugin.show(
      _notificationId,
      'Geo tracking active',
      'Location updates about every $intervalMinutes minutes',
      NotificationDetails(android: androidDetails),
    );
  }

  Future<void> cancelTrackingNotification() async {
    if (!_initialized) {
      await initialize();
    }
    await _plugin.cancel(_notificationId);
  }
}
