import 'dart:io';
import 'dart:math';

import 'package:android_id/android_id.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdentityService {
  static const String _deviceIdKey = 'attendance_device_identifier';
  static const AndroidId _androidIdPlugin = AndroidId();

  Future<Map<String, String>> getDeviceMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    final identifier = await _resolveIdentifier(prefs);

    final vendor = _platformVendor();
    final model = '${Platform.operatingSystem}-${Platform.operatingSystemVersion}'.replaceAll('\n', ' ');

    return {
      'deviceIdentifier': identifier,
      'deviceName': '$vendor Attendance App',
      'deviceModel': model,
      'deviceVendor': vendor,
    };
  }

  Future<String> _resolveIdentifier(SharedPreferences prefs) async {
    if (Platform.isAndroid) {
      try {
        final androidId = await _androidIdPlugin.getId();
        if (androidId != null && androidId.isNotEmpty) {
          final stableIdentifier = 'android-${androidId.toLowerCase()}';
          await prefs.setString(_deviceIdKey, stableIdentifier);
          return stableIdentifier;
        }
      } catch (_) {
      }
    }

    final cachedIdentifier = prefs.getString(_deviceIdKey);
    if (cachedIdentifier != null && cachedIdentifier.isNotEmpty) {
      return cachedIdentifier;
    }

    final generatedIdentifier = _generateIdentifier();
    await prefs.setString(_deviceIdKey, generatedIdentifier);
    return generatedIdentifier;
  }

  String _generateIdentifier() {
    final random = Random.secure();
    final suffix = List.generate(8, (_) => random.nextInt(16).toRadixString(16)).join();
    return 'android-${DateTime.now().millisecondsSinceEpoch}-$suffix';
  }

  String _platformVendor() {
    if (Platform.isAndroid) {
      return 'Android';
    }
    if (Platform.isIOS) {
      return 'iOS';
    }
    return Platform.operatingSystem;
  }
}