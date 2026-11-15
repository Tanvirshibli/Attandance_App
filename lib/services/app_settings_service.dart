import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/face_capture_strings.dart';

/// Persisted, account-independent preferences for the app itself.
///
/// It holds the face-capture language flag and the local mirror of the
/// biometric switches plus the fingerprint credential this device enrolled.
/// The switches themselves are owned by the server
/// (`/api/v1/mobile/biometric-preferences`); the values here are what the app
/// shows when the server cannot be reached, and what the check-in flow reads
/// before it opens a camera or a fingerprint prompt.
class AppSettingsService {
  AppSettingsService._();

  static final AppSettingsService instance = AppSettingsService._();

  static const String _faceCaptureBanglaKey = 'face_capture_bangla';
  static const String _biometricLoginFingerprintKey =
      'biometric_login_fingerprint';
  static const String _biometricLoginFaceKey = 'biometric_login_face';
  static const String _biometricCheckinFingerprintKey =
      'biometric_checkin_fingerprint';
  static const String _biometricCheckinFaceKey = 'biometric_checkin_face';
  static const String _biometricCredentialIdKey = 'biometric_credential_id';
  static const String _biometricKeyAliasKey = 'biometric_key_alias';
  static const String _biometricFaceLoginEnabledKey =
      'biometric_face_login_enabled';

  /// Exposed so the settings tile can rebuild its switch from stored state.
  final ValueNotifier<bool> faceCaptureBangla = ValueNotifier<bool>(false);

  /// Whether fingerprint sign-in is offered on the login screen.
  final ValueNotifier<bool> biometricLoginFingerprint = ValueNotifier<bool>(false);

  /// Whether a face match may sign the user in (needs a stored refresh token).
  final ValueNotifier<bool> biometricLoginFace = ValueNotifier<bool>(false);

  /// Whether the check-in flow may use the fingerprint authorisation path.
  final ValueNotifier<bool> biometricCheckinFingerprint =
      ValueNotifier<bool>(false);

  /// Whether the check-in flow may use the face path. Off by default, matching
  /// the server (`MobileBiometricCredential::preferencesFrom` defaults
  /// `checkin.face` to false): a flag that started true locally made the app
  /// offer a flow the backend would reject until the first preferences sync.
  final ValueNotifier<bool> biometricCheckinFace = ValueNotifier<bool>(false);

  /// Server-side id of this device's fingerprint credential (null = none).
  final ValueNotifier<String?> biometricCredentialId =
      ValueNotifier<String?>(null);

  /// Android Keystore alias holding the signing key for [biometricCredentialId].
  final ValueNotifier<String?> biometricKeyAlias = ValueNotifier<String?>(null);

  /// Mirrors [biometricLoginFace]; kept separately because a face login also
  /// requires the encrypted refresh token that [AuthService] stores.
  final ValueNotifier<bool> biometricFaceLoginEnabled = ValueNotifier<bool>(false);

  bool _loaded = false;

  /// Reads the persisted flags. Cheap and local — safe to await before the first
  /// frame, and safe to call again.
  Future<void> init() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      faceCaptureBangla.value = prefs.getBool(_faceCaptureBanglaKey) ?? false;
      biometricLoginFingerprint.value =
          prefs.getBool(_biometricLoginFingerprintKey) ?? false;
      biometricLoginFace.value =
          prefs.getBool(_biometricLoginFaceKey) ?? false;
      biometricCheckinFingerprint.value =
          prefs.getBool(_biometricCheckinFingerprintKey) ?? false;
      biometricCheckinFace.value =
          prefs.getBool(_biometricCheckinFaceKey) ?? false;
      biometricCredentialId.value = prefs.getString(_biometricCredentialIdKey);
      biometricKeyAlias.value = prefs.getString(_biometricKeyAliasKey);
      biometricFaceLoginEnabled.value =
          prefs.getBool(_biometricFaceLoginEnabledKey) ?? false;
      _loaded = true;
    } catch (error) {
      // A preferences read must never block the app: the defaults apply.
      debugPrint('AppSettingsService.init failed: $error');
    }
  }

  FaceCaptureStrings get faceCaptureStrings => faceCaptureBangla.value
      ? FaceCaptureStrings.bangla
      : FaceCaptureStrings.english;

  bool get hasBiometricCredential =>
      (biometricCredentialId.value ?? '').isNotEmpty;

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

  Future<void> setBiometricLoginFingerprint(bool enabled) =>
      _setBool(_biometricLoginFingerprintKey, biometricLoginFingerprint, enabled);

  Future<void> setBiometricLoginFace(bool enabled) =>
      _setBool(_biometricLoginFaceKey, biometricLoginFace, enabled);

  Future<void> setBiometricCheckinFingerprint(bool enabled) => _setBool(
        _biometricCheckinFingerprintKey,
        biometricCheckinFingerprint,
        enabled,
      );

  Future<void> setBiometricCheckinFace(bool enabled) =>
      _setBool(_biometricCheckinFaceKey, biometricCheckinFace, enabled);

  Future<void> setBiometricFaceLoginEnabled(bool enabled) => _setBool(
        _biometricFaceLoginEnabledKey,
        biometricFaceLoginEnabled,
        enabled,
      );

  Future<void> setBiometricCredential({
    required String credentialId,
    required String keyAlias,
  }) async {
    biometricCredentialId.value = credentialId;
    biometricKeyAlias.value = keyAlias;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_biometricCredentialIdKey, credentialId);
      await prefs.setString(_biometricKeyAliasKey, keyAlias);
    } catch (error) {
      debugPrint('AppSettingsService.setBiometricCredential failed: $error');
    }
  }

  Future<void> clearBiometricCredential() async {
    biometricCredentialId.value = null;
    biometricKeyAlias.value = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_biometricCredentialIdKey);
      await prefs.remove(_biometricKeyAliasKey);
    } catch (error) {
      debugPrint('AppSettingsService.clearBiometricCredential failed: $error');
    }
  }

  Future<void> _setBool(
    String key,
    ValueNotifier<bool> notifier,
    bool value,
  ) async {
    if (notifier.value != value) {
      notifier.value = value;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (error) {
      debugPrint('AppSettingsService.$key write failed: $error');
    }
  }
}
