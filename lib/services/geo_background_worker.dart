import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'geo_tracking_service.dart';

const String geoBackgroundTaskName = 'pphl_geo_tracking_task';

@pragma('vm:entry-point')
void geoBackgroundCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('geo_tracking_enabled') ?? false;
      if (!enabled) return true;

      final service = GeoTrackingService();
      await service.captureAndQueue(source: 'background');
      await service.flushQueue();
      return true;
    } catch (error) {
      debugPrint('Geo background task failed: $error');
      return false;
    }
  });
}

class GeoBackgroundWorker {
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      await Workmanager().initialize(geoBackgroundCallbackDispatcher);
      _initialized = true;
    } catch (error) {
      debugPrint('Workmanager init failed: $error');
    }
  }

  static Future<void> registerPeriodicTask() async {
    if (!_initialized) return;
    try {
      await Workmanager().registerPeriodicTask(
        geoBackgroundTaskName,
        geoBackgroundTaskName,
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingWorkPolicy.update,
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
      );
    } catch (error) {
      debugPrint('Workmanager register failed: $error');
    }
  }

  static Future<void> cancelPeriodicTask() async {
    if (!_initialized) return;
    try {
      await Workmanager().cancelByUniqueName(geoBackgroundTaskName);
    } catch (error) {
      debugPrint('Workmanager cancel failed: $error');
    }
  }
}
