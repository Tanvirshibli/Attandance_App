import 'package:flutter/foundation.dart';

import 'app_settings_service.dart';
import 'biometric_api_service.dart';

/// The four biometric switches, read from the server on demand and mirrored
/// locally so the login screen and the check-in flow work offline.
///
/// The server owns the values (`PUT /api/v1/mobile/biometric-preferences`), the
/// local copy is what the UI binds to. A failed save rolls the local copy back
/// so the switch never claims a state the server rejected.
class BiometricPreferencesService {
  BiometricPreferencesService._();

  static final BiometricPreferencesService instance =
      BiometricPreferencesService._();

  final AppSettingsService _settings = AppSettingsService.instance;
  final BiometricApiService _api = BiometricApiService();

  ValueNotifier<bool> get loginFace => _settings.biometricLoginFace;
  ValueNotifier<bool> get loginFingerprint =>
      _settings.biometricLoginFingerprint;
  ValueNotifier<bool> get checkinFace => _settings.biometricCheckinFace;
  ValueNotifier<bool> get checkinFingerprint =>
      _settings.biometricCheckinFingerprint;

  BiometricPreferencesData get current => BiometricPreferencesData(
        loginFace: loginFace.value,
        loginFingerprint: loginFingerprint.value,
        checkinFace: checkinFace.value,
        checkinFingerprint: checkinFingerprint.value,
      );

  /// Pulls the server's view and adopts it. Offline, the local values stay.
  Future<void> load() async {
    final snapshot = await _api.fetchCredentials();
    final preferences = snapshot?.preferences;
    if (preferences == null) return;
    await adoptSnapshot(preferences);
  }

  /// Optimistic save: the switch moves immediately, and moves back if the
  /// server rejects it (a 422 for a combination it will not accept, say).
  Future<bool> save({
    bool? loginFace,
    bool? loginFingerprint,
    bool? checkinFace,
    bool? checkinFingerprint,
  }) async {
    final previous = current;
    final next = previous.copyWith(
      loginFace: loginFace,
      loginFingerprint: loginFingerprint,
      checkinFace: checkinFace,
      checkinFingerprint: checkinFingerprint,
    );

    await _applyLocally(next);
    final saved = await _api.savePreferences(next);
    if (saved == null) {
      await _applyLocally(previous);
      return false;
    }
    // Only a 2xx is mirrored, and the mirror becomes the server's snapshot
    // rather than what was sent: the backend may have clamped a combination.
    await adoptSnapshot(saved);
    return true;
  }

  /// Sends the current mirror as-is, without [save]'s optimistic apply.
  ///
  /// For callers whose local state already changed for a reason the server has
  /// to be told about (a revoked or invalidated key turns every punch into a
  /// 422 while the server still believes fingerprint is on). The local copy is
  /// the truth there, so a failed push reports false instead of rolling back.
  Future<bool> pushCurrent() async {
    final pushed = await _api.savePreferences(current);
    return pushed != null;
  }

  /// Adopts a snapshot the server just returned, with no extra round trip.
  Future<void> adoptSnapshot(BiometricPreferencesData preferences) =>
      _applyLocally(preferences);

  Future<void> _applyLocally(BiometricPreferencesData preferences) async {
    await _settings.setBiometricLoginFace(preferences.loginFace);
    await _settings.setBiometricLoginFingerprint(preferences.loginFingerprint);
    await _settings.setBiometricCheckinFace(preferences.checkinFace);
    await _settings.setBiometricCheckinFingerprint(
      preferences.checkinFingerprint,
    );
    // The login screen keys off the "enabled" flag, which tracks the same
    // preference; the encrypted token it refreshes from is checked separately
    // when the flow actually runs.
    await _settings.setBiometricFaceLoginEnabled(preferences.loginFace);
  }
}
