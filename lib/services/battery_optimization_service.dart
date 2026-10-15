import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Battery-optimisation exemption status for Android, backed by the
/// `com.pphl.employee_attendance/battery_optimization` MethodChannel registered
/// in MainActivity.kt.
///
/// Android may suspend background geo work while the app is optimised, so the
/// Geo Tracking screen offers the system exemption list. Both calls are safe
/// everywhere: a non-Android platform or a channel error reports `false`
/// rather than throwing, matching the platform-guard style the app's other
/// MethodChannel service uses.
class BatteryOptimizationService {
  static const _channel =
      MethodChannel('com.pphl.employee_attendance/battery_optimization');

  /// Whether the app is exempt from battery optimisations.
  ///
  /// Returns false on any error or when not running on Android.
  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return false;
    try {
      final ignoring =
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return ignoring ?? false;
    } catch (e) {
      debugPrint(
        'BatteryOptimizationService.isIgnoringBatteryOptimizations: $e',
      );
      return false;
    }
  }

  /// Opens the system's battery-optimisation exemption list.
  ///
  /// Returns false on any error or when not running on Android.
  Future<bool> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final opened =
          await _channel.invokeMethod<bool>('openBatteryOptimizationSettings');
      return opened ?? false;
    } catch (e) {
      debugPrint(
        'BatteryOptimizationService.openBatteryOptimizationSettings: $e',
      );
      return false;
    }
  }
}
