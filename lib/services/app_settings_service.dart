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

  /// `granted` / `declined` / absent. Asked once, then remembered, so the
  /// auto-enrolment prompt never nags a user who already answered.
  static const String _biometricEnrollConsentKey = 'biometric_enroll_consent';

  /// Set once the one-time "turn every biometric setting on" push has landed.
  static const String _biometricDefaultsAppliedKey =
      'biometric_defaults_applied';

  /// Exposed so the settings tile can rebuild its switch from stored state.
  final ValueNotifier<bool> faceCaptureBangla = ValueNotifier<bool>(false);

  /// Whether fingerprint sign-in is offered on the login screen.
  ///
  /// The four biometric flags start **on**: they are what the app offers until
  /// the user deliberately turns something off, and the one-shot server push in
  /// `BiometricPreferencesService.applyDefaultsOnce` makes the server agree. A
  /// server snapshot still wins once it arrives.
  final ValueNotifier<bool> biometricLoginFingerprint = ValueNotifier<bool>(true);

  /// Whether a face match may sign the user in (needs a stored refresh token).
  final ValueNotifier<bool> biometricLoginFace = ValueNotifier<bool>(true);

  /// Whether the check-in flow may use the fingerprint authorisation path.
  final ValueNotifier<bool> biometricCheckinFingerprint =
      ValueNotifier<bool>(true);

  /// Whether the check-in flow may use the face path.
  ///
  /// On by default, and the punch gate only demands a fingerprint proof when
  /// this is off — keeping it on is what guarantees a punch is never blocked on
  /// a phone that cannot provide a fingerprint.
  final ValueNotifier<bool> biometricCheckinFace = ValueNotifier<bool>(true);

  /// Server-side id of this device's fingerprint credential (null = none).
  final ValueNotifier<String?> biometricCredentialId =
      ValueNotifier<String?>(null);

  /// Android Keystore alias holding the signing key for [biometricCredentialId].
  final ValueNotifier<String?> biometricKeyAlias = ValueNotifier<String?>(null);

  /// Mirrors [biometricLoginFace]; kept separately because a face login also
  /// requires the encrypted refresh token that [AuthService] stores.
  final ValueNotifier<bool> biometricFaceLoginEnabled = ValueNotifier<bool>(true);

  /// The user's one-time answer to "enable fingerprint sign-in here?".
  final ValueNotifier<String?> biometricEnrollConsent =
      ValueNotifier<String?>(null);

  /// Whether the one-time defaults push has already landed on the server.
  final ValueNotifier<bool> biometricDefaultsApplied =
      ValueNotifier<bool>(false);

  bool _loaded = false;

  /// Reads the persisted flags. Cheap and local — safe to await before the first
  /// frame, and safe to call again.
  Future<void> init() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      faceCaptureBangla.value = prefs.getBool(_faceCaptureBanglaKey) ?? false;
      biometricLoginFingerprint.value =
          prefs.getBool(_biometricLoginFingerprintKey) ?? true;
      biometricLoginFace.value =
          prefs.getBool(_biometricLoginFaceKey) ?? true;
      biometricCheckinFingerprint.value =
          prefs.getBool(_biometricCheckinFingerprintKey) ?? true;
      biometricCheckinFace.value =
          prefs.getBool(_biometricCheckinFaceKey) ?? true;
      biometricCredentialId.value = prefs.getString(_biometricCredentialIdKey);
      biometricKeyAlias.value = prefs.getString(_biometricKeyAliasKey);
      biometricFaceLoginEnabled.value =
          prefs.getBool(_biometricFaceLoginEnabledKey) ?? true;
      biometricEnrollConsent.value = prefs.getString(_biometricEnrollConsentKey);
      biometricDefaultsApplied.value =
          prefs.getBool(_biometricDefaultsAppliedKey) ?? false;
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

  Future<void> setBiometricFaceLoginEnabled(bool enabled) async {
    await _setBool(_biometricFaceLoginEnabledKey, biometricFaceLoginEnabled, enabled);
    // The login screen renders from `biometricLoginFace`; leaving the two out of
    // step is how a "face login is on" switch produced no face button.
    await setBiometricLoginFace(enabled);
  }

  /// Records the one-time answer to the enrolment prompt (`granted`/`declined`).
  Future<void> setBiometricEnrollConsent(String value) async {
    biometricEnrollConsent.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_biometricEnrollConsentKey, value);
    } catch (error) {
      debugPrint('AppSettingsService.setBiometricEnrollConsent failed: $error');
    }
  }

  /// Marks the one-time biometric defaults push as landed.
  Future<void> setBiometricDefaultsApplied(bool applied) async {
    biometricDefaultsApplied.value = applied;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_biometricDefaultsAppliedKey, applied);
    } catch (error) {
      debugPrint('AppSettingsService.setBiometricDefaultsApplied failed: $error');
    }
  }

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
