import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Why a biometric platform call could not complete.
enum BiometricFailure {
  unavailable,
  noneEnrolled,
  keyInvalidated,
  userCanceled,
  lockout,
  unknown,
}

class BiometricPlatformException implements Exception {
  const BiometricPlatformException(this.failure, this.message);

  final BiometricFailure failure;
  final String message;

  @override
  String toString() => 'BiometricPlatformException(${failure.name}): $message';
}

class BiometricAvailability {
  const BiometricAvailability({
    required this.available,
    required this.reason,
    this.failure,
  });

  final bool available;
  final String reason;
  final BiometricFailure? failure;

  static const BiometricAvailability unsupported = BiometricAvailability(
    available: false,
    reason: 'Biometric sign-in is only available on Android devices.',
    failure: BiometricFailure.unavailable,
  );

  static const BiometricAvailability ready = BiometricAvailability(
    available: true,
    reason: 'Ready',
  );
}

/// Thin wrapper over `com.pphl.attendance/biometric_keystore`.
///
/// Android never exposes fingerprint templates, so "enrolment" here means: the
/// device's own enrolled fingerprint authorises an ECDSA P-256 key in the
/// Android Keystore. The channel generates that key, hands back its public half,
/// and signs server nonces once the user passes the system prompt.
class BiometricPlatformService {
  BiometricPlatformService._();

  static final BiometricPlatformService instance = BiometricPlatformService._();

  static const MethodChannel _channel =
      MethodChannel('com.pphl.attendance/biometric_keystore');

  /// The channel only exists in the Android host, so every other platform —
  /// and any build without the plugin registered — degrades to "unavailable".
  bool get isSupported {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  Future<BiometricAvailability> canAuthenticate() async {
    if (!isSupported) return BiometricAvailability.unsupported;

    try {
      final raw = await _channel
          .invokeMapMethod<String, dynamic>('canAuthenticate');
      if (raw == null) return BiometricAvailability.unsupported;

      final available = raw['available'] == true;
      return BiometricAvailability(
        available: available,
        reason: raw['reason']?.toString() ??
            (available ? 'Ready' : 'Biometric sign-in is unavailable.'),
        failure: available ? null : _failureFor(raw['code']?.toString()),
      );
    } on MissingPluginException {
      return BiometricAvailability.unsupported;
    } on PlatformException catch (error) {
      return BiometricAvailability(
        available: false,
        reason: error.message ?? 'Biometric sign-in is unavailable.',
        failure: _failureFor(error.code),
      );
    } catch (_) {
      return BiometricAvailability.unsupported;
    }
  }

  Future<void> generateKey(String alias) async {
    await _invoke('generateKey', {'alias': alias});
  }

  Future<String?> getPublicKey(String alias) async {
    if (!isSupported) return null;
    try {
      return await _channel
          .invokeMethod<String>('getPublicKey', {'alias': alias});
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String> sign({
    required String alias,
    required String dataBase64,
  }) async {
    if (!isSupported) {
      throw const BiometricPlatformException(
        BiometricFailure.unavailable,
        'Biometric sign-in is only available on Android devices.',
      );
    }

    try {
      final signature = await _channel.invokeMethod<String>('sign', {
        'alias': alias,
        'data': dataBase64,
      });
      if (signature == null || signature.isEmpty) {
        throw const BiometricPlatformException(
          BiometricFailure.unknown,
          'The fingerprint signature could not be produced.',
        );
      }
      return signature;
    } on MissingPluginException {
      throw const BiometricPlatformException(
        BiometricFailure.unavailable,
        'Biometric sign-in is not available in this build.',
      );
    } on PlatformException catch (error) {
      throw BiometricPlatformException(
        _failureFor(error.code),
        error.message ?? 'Fingerprint verification failed.',
      );
    }
  }

  Future<bool> hasKey(String alias) async {
    if (!isSupported) return false;
    try {
      final has = await _channel.invokeMethod<bool>('hasKey', {'alias': alias});
      return has ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteKey(String alias) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('deleteKey', {'alias': alias});
    } on MissingPluginException {
      // Nothing was ever created on this build.
    } on PlatformException catch (error) {
      debugPrint('BiometricPlatformService.deleteKey failed: ${error.code}');
    } catch (_) {}
  }

  Future<void> _invoke(String method, Map<String, dynamic> arguments) async {
    if (!isSupported) {
      throw const BiometricPlatformException(
        BiometricFailure.unavailable,
        'Biometric sign-in is only available on Android devices.',
      );
    }

    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      throw const BiometricPlatformException(
        BiometricFailure.unavailable,
        'Biometric sign-in is not available in this build.',
      );
    } on PlatformException catch (error) {
      throw BiometricPlatformException(
        _failureFor(error.code),
        error.message ?? 'The fingerprint key could not be created.',
      );
    }
  }

  BiometricFailure _failureFor(String? code) {
    switch (code) {
      case 'unavailable':
        return BiometricFailure.unavailable;
      case 'none_enrolled':
        return BiometricFailure.noneEnrolled;
      case 'key_invalidated':
        return BiometricFailure.keyInvalidated;
      case 'user_canceled':
        return BiometricFailure.userCanceled;
      case 'lockout':
        return BiometricFailure.lockout;
      default:
        return BiometricFailure.unknown;
    }
  }
}
