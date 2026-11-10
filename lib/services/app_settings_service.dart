import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/face_capture_strings.dart';

/// Persisted, account-independent preferences for the app itself.
///
/// Today it holds one flag: whether the face-capture screen speaks Bangla. The
/// profile screen's toggle writes it, [CheckInScreen] reads
/// [faceCaptureStrings] when it is created, so a change takes effect on the next
/// capture without a restart or a re-login.
class AppSettingsService {
  AppSettingsService._();

  static final AppSettingsService instance = AppSettingsService._();

  static const String _faceCaptureBanglaKey = 'face_capture_bangla';

  /// Exposed so the settings tile can rebuild its switch from stored state.
  final ValueNotifier<bool> faceCaptureBangla = ValueNotifier<bool>(false);

  bool _loaded = false;

  /// Reads the persisted flag. Cheap and local — safe to await before the first
  /// frame, and safe to call again.
  Future<void> init() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      faceCaptureBangla.value = prefs.getBool(_faceCaptureBanglaKey) ?? false;
      _loaded = true;
    } catch (error) {
      // A preferences read must never block the app: the default is English.
      debugPrint('AppSettingsService.init failed: $error');
    }
  }

  FaceCaptureStrings get faceCaptureStrings => faceCaptureBangla.value
      ? FaceCaptureStrings.bangla
      : FaceCaptureStrings.english;

  Future<void> setFaceCaptureBangla(bool enabled) async {
    if (faceCaptureBangla.value != enabled) {
      faceCaptureBangla.value = enabled;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_faceCaptureBanglaKey, enabled);
    } catch (error) {
      debugPrint('AppSettingsService.setFaceCaptureBangla failed: $error');
    }
  }
}
