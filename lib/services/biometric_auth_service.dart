import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:package_info_plus/package_info_plus.dart';

import 'app_settings_service.dart';
import 'biometric_api_service.dart';
import 'biometric_platform_service.dart';
import 'biometric_preferences_service.dart';
import 'device_identity_service.dart';

class BiometricResult {
  const BiometricResult({
    required this.success,
    required this.message,
    this.authorizationId,
  });

  const BiometricResult.failure(this.message)
      : success = false,
        authorizationId = null;

  final bool success;
  final String message;
  final String? authorizationId;
}

class BiometricSignatureResult {
  const BiometricSignatureResult({
    required this.success,
    required this.message,
    this.credentialId,
    this.nonce,
    this.signature,
  });

  const BiometricSignatureResult.failure(this.message)
      : success = false,
        credentialId = null,
        nonce = null,
        signature = null;

  final bool success;
  final String message;
  final String? credentialId;
  final String? nonce;
  final String? signature;
}

/// Ownership of this device's fingerprint credential.
///
/// Enrolment stores the public half of a Keystore-held ECDSA P-256 key with the
/// backend; every later signature is a server nonce signed after the device's
/// own fingerprint prompt. No fingerprint data ever leaves the device.
class BiometricAuthService {
  BiometricAuthService._();

  static final BiometricAuthService instance = BiometricAuthService._();

  static const String _noCredentialMessage =
      'No fingerprint is enrolled on this device. Sign in with your password '
      'and enroll it in Profile → Biometrics.';

  static const String _keyInvalidatedMessage =
      'This device\'s fingerprint changed, so the saved key was disabled. '
      'Sign in with your password and enroll your fingerprint again in '
      'Profile → Biometrics.';

  /// Appended when the server could not be told that fingerprint is off. The
  /// procedure itself still completed on the device; only the mirror the server
  /// gates on is stale, and a stale `checkin.fingerprint=true` makes every
  /// punch 422 until it is corrected.
  static const String _preferencesNotPushedMessage =
      ' The server could not be told, so check-in may be refused until you are '
      'back online — try again then.';

  final BiometricPlatformService _platform = BiometricPlatformService.instance;
  final BiometricApiService _api = BiometricApiService();
  final BiometricPreferencesService _preferences =
      BiometricPreferencesService.instance;
  final DeviceIdentityService _deviceIdentity = DeviceIdentityService();
  final AppSettingsService _settings = AppSettingsService.instance;

  String? get credentialId => _settings.biometricCredentialId.value;

  String? get keyAlias => _settings.biometricKeyAlias.value;

  bool get hasCredential => _settings.hasBiometricCredential;

  Future<BiometricAvailability> availability() => _platform.canAuthenticate();

  /// Enrols this device's fingerprint when it is safe and the user agreed.
  ///
  /// Called after a password sign-in, which is the only moment the app may act
  /// on the user's behalf. Three outcomes:
  /// * a credential already exists → nothing to do;
  /// * the phone has no usable sensor or no fingerprint set up in Android →
  ///   defer with the reason (Android cannot create a biometric for the user);
  /// * otherwise ask once. The answer is remembered, so a user who declines is
  ///   never asked again, and a later key invalidation asks afresh because that
  ///   is a genuinely new device state.
  ///
  /// [confirm] is supplied by the caller so this service stays UI-free.
  Future<BiometricResult> ensureEnrolled({
    required Future<bool> Function(String title, String message) confirm,
  }) async {
    if (hasCredential) {
      return const BiometricResult(
        success: true,
        message: 'Fingerprint already enrolled.',
      );
    }

    final availability = await _platform.canAuthenticate();
    if (!availability.available) {
      return BiometricResult.failure(availability.reason);
    }

    // The login screen is the only caller that asks; a background caller can
    // pass a confirm that returns false to stay silent.
    final consent = _settings.biometricEnrollConsent.value;
    if (consent == 'granted') {
      return enrollFingerprint();
    }
    if (consent == 'declined') {
      return const BiometricResult(
        success: false,
        message: 'Fingerprint sign-in was declined on this device.',
      );
    }

    final accepted = await confirm(
      'Enable fingerprint sign-in?',
      'Use your fingerprint to sign in and to confirm check-in and check-out on '
          'this phone. You can turn it off any time in Profile → Biometrics.',
    );
    await _settings.setBiometricEnrollConsent(accepted ? 'granted' : 'declined');

    if (!accepted) {
      return const BiometricResult(
        success: false,
        message: 'Fingerprint sign-in was declined on this device.',
      );
    }

    return enrollFingerprint();
  }

  /// Creates (or re-creates) the Keystore key and registers its public half.
  Future<BiometricResult> enrollFingerprint() async {
    final availability = await _platform.canAuthenticate();
    if (!availability.available) {
      return BiometricResult.failure(availability.reason);
    }

    final id = hasCredential ? credentialId! : _generateCredentialId();
    final alias = 'pphl_bio_$id';

    try {
      await _platform.generateKey(alias);
    } on BiometricPlatformException catch (error) {
      return BiometricResult.failure(_messageFor(error));
    }

    final publicKey = await _platform.getPublicKey(alias);
    if (publicKey == null || publicKey.isEmpty) {
      await _platform.deleteKey(alias);
      return const BiometricResult.failure(
        'The fingerprint key could not be read back. Please try again.',
      );
    }

    final metadata = await _deviceIdentity.getDeviceMetadata();
    final saved = await _api.registerCredential(
      credentialId: id,
      publicKey: publicKey,
      keyAlias: alias,
      deviceIdentifier: metadata['deviceIdentifier'] ?? '',
      deviceName: metadata['deviceName'] ?? '',
      deviceModel: metadata['deviceModel'] ?? '',
      deviceVendor: metadata['deviceVendor'] ?? '',
      appVersion: await _appVersion(),
      sdkVersion: Platform.operatingSystemVersion,
    );

    if (!saved) {
      await _platform.deleteKey(alias);
      return const BiometricResult.failure(
        'The fingerprint could not be registered with the server. Check your '
        'connection and try again.',
      );
    }

    await _settings.setBiometricCredential(credentialId: id, keyAlias: alias);
    await _settings.setBiometricLoginFingerprint(true);
    await _settings.setBiometricCheckinFingerprint(true);
    // Preserve the face switches: enabling fingerprint must not reset them.
    final preferences = await _api.savePreferences(
      BiometricPreferencesData(
        loginFace: _settings.biometricLoginFace.value,
        loginFingerprint: true,
        checkinFace: _settings.biometricCheckinFace.value,
        checkinFingerprint: true,
      ),
    );
    // The snapshot the server stored is what the login and check-in gates must
    // read from now on — it may have clamped a combination it will not accept,
    // and the local flags set above are only the request, not the outcome.
    if (preferences != null) {
      await _preferences.adoptSnapshot(preferences);
    }

    return const BiometricResult(
      success: true,
      message: 'Fingerprint enrolled on this device.',
    );
  }

  /// Issues a server challenge for [purpose] (`login` or `punch`) and signs it
  /// with the Keystore key after the device's own fingerprint prompt.
  Future<BiometricSignatureResult> signChallenge({
    required String purpose,
  }) async {
    final id = credentialId;
    final alias = keyAlias;
    if (id == null || id.isEmpty || alias == null || alias.isEmpty) {
      return const BiometricSignatureResult.failure(_noCredentialMessage);
    }

    if (!await _platform.hasKey(alias)) {
      final preferencesPushed = await _handleInvalidation();
      return BiometricSignatureResult.failure(
        preferencesPushed
            ? _keyInvalidatedMessage
            : _keyInvalidatedMessage + _preferencesNotPushedMessage,
      );
    }

    final challenge = await _api.requestChallenge(
      credentialId: id,
      purpose: purpose,
    );
    if (challenge == null) {
      return const BiometricSignatureResult.failure(
        'The server could not issue a fingerprint challenge. Check your '
        'connection and try again.',
      );
    }

    try {
      final signature = await _platform.sign(
        alias: alias,
        dataBase64: base64Encode(utf8.encode(challenge.nonce)),
      );
      return BiometricSignatureResult(
        success: true,
        message: 'Fingerprint verified.',
        credentialId: id,
        nonce: challenge.nonce,
        signature: signature,
      );
    } on BiometricPlatformException catch (error) {
      if (error.failure == BiometricFailure.keyInvalidated) {
        final preferencesPushed = await _handleInvalidation();
        return BiometricSignatureResult.failure(
          preferencesPushed
              ? _keyInvalidatedMessage
              : _keyInvalidatedMessage + _preferencesNotPushedMessage,
        );
      }
      return BiometricSignatureResult.failure(_messageFor(error));
    }
  }

  /// Full punch authorization: challenge → fingerprint signature → server grant
  /// that the attendance submission then quotes.
  Future<BiometricResult> authorizePunch({required String direction}) async {
    final signed = await signChallenge(purpose: 'punch');
    if (!signed.success) {
      return BiometricResult.failure(signed.message);
    }

    final metadata = await _deviceIdentity.getDeviceMetadata();
    final authorization = await _api.requestPunchAuthorization(
      credentialId: signed.credentialId!,
      nonce: signed.nonce!,
      signature: signed.signature!,
      direction: direction,
      deviceIdentifier: metadata['deviceIdentifier'] ?? '',
    );

    if (authorization == null) {
      return const BiometricResult.failure(
        'Attendance could not be authorized. Check your connection and try '
        'again, or use face verification.',
      );
    }

    return BiometricResult(
      success: true,
      message: 'Fingerprint verified.',
      authorizationId: authorization.authorizationId,
    );
  }

  /// Deletes the server credential and the Keystore key, then clears the local
  /// flags and tells the server to stop requiring a fingerprint the device no
  /// longer has. Offline, the device side still goes away and the failure is
  /// reported so the user can retry.
  Future<BiometricResult> revoke() async {
    final id = credentialId;
    final alias = keyAlias;

    var serverDeleted = true;
    if (id != null && id.isNotEmpty) {
      serverDeleted = await _api.deleteCredential(credentialId: id);
    }
    if (alias != null && alias.isNotEmpty) {
      await _platform.deleteKey(alias);
    }

    await _settings.clearBiometricCredential();
    await _settings.setBiometricLoginFingerprint(false);
    await _settings.setBiometricCheckinFingerprint(false);
    // A deliberate removal is a new answer: the auto-enrolment prompt may be
    // offered again if the user later changes their mind.
    await _settings.setBiometricEnrollConsent('declined');
    // Clearing only the local flags leaves the server believing fingerprint is
    // on: its preferences gate requires a credential, so every later punch is
    // rejected with a 422 the device has no way to satisfy. The push is the
    // half that matters; a failure must not block the UI, only be reported.
    final preferencesPushed = await _preferences.pushCurrent();
    final notPushedNote =
        preferencesPushed ? '' : _preferencesNotPushedMessage;

    if (!serverDeleted) {
      return BiometricResult(
        success: false,
        message: 'Removed from this device. The server could not be reached, so '
            'the old credential may still be listed — remove it again when '
            'you are online.$notPushedNote',
      );
    }

    return BiometricResult(
      success: true,
      message: 'Fingerprint removed from this device.$notPushedNote',
    );
  }

  /// A key whose fingerprint set changed is unusable, so the credential it
  /// belongs to is retired immediately rather than left to fail every attempt.
  ///
  /// Returns whether the server accepted the updated preferences — the caller
  /// reports a failed push in its result rather than hiding it, because a stale
  /// `checkin.fingerprint` on the server blocks check-in until it is fixed.
  Future<bool> _handleInvalidation() async {
    final id = credentialId;
    final alias = keyAlias;
    if (id != null && id.isNotEmpty) {
      await _api.deleteCredential(credentialId: id);
    }
    if (alias != null && alias.isNotEmpty) {
      await _platform.deleteKey(alias);
    }
    await _settings.clearBiometricCredential();
    await _settings.setBiometricLoginFingerprint(false);
    await _settings.setBiometricCheckinFingerprint(false);
    return _preferences.pushCurrent();
  }

  String _messageFor(BiometricPlatformException error) {
    switch (error.failure) {
      case BiometricFailure.noneEnrolled:
        return 'No fingerprint is set up in this phone\'s settings. Add one '
            'there first, then enroll again.';
      case BiometricFailure.userCanceled:
        return 'Fingerprint verification was cancelled.';
      case BiometricFailure.lockout:
        return 'Too many failed fingerprint attempts. Wait a moment and try '
            'again, or sign in with your password.';
      case BiometricFailure.unavailable:
        return error.message;
      case BiometricFailure.keyInvalidated:
        return _keyInvalidatedMessage;
      case BiometricFailure.unknown:
        return error.message.isEmpty
            ? 'Fingerprint verification failed. Please try again.'
            : error.message;
    }
  }

  Future<String> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return 'unknown';
    }
  }

  String _generateCredentialId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    // RFC 4122 v4 layout, so the id is safe for a UUID column server-side.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
