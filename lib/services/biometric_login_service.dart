import 'dart:convert';
import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/face_registration_data.dart';
import '../utils/user_facing_error.dart';
import 'auth_service.dart';
import 'biometric_api_service.dart';
import 'biometric_auth_service.dart';
import 'device_identity_service.dart';
import 'endpoint_config_service.dart';
import 'face_recognition_service.dart';

enum BiometricLoginMethod { fingerprint, face }

enum FaceLoginBlocker { ready, noTemplate, notLinked, serverUnavailable }

enum _FaceRegistrationStatus { found, missing, unauthorized, unavailable }

class _FaceRegistrationFetch {
  const _FaceRegistrationFetch(this.status, [this.registration]);

  final _FaceRegistrationStatus status;
  final FaceRegistrationData? registration;
}

class BiometricLoginOutcome {
  const BiometricLoginOutcome.success(this.message) : success = true;

  const BiometricLoginOutcome.failure(this.message) : success = false;

  final bool success;
  final String message;
}

/// The two passwordless sign-in flows.
///
/// Fingerprint: server challenge → Keystore signature → `biometric-login`.
/// Face: a local template match against the device's own template, then a JWT
/// refresh with the token kept in encrypted storage. Neither touches the stored
/// password, and neither throws: every failure comes back as a message the login
/// screen can show.
class BiometricLoginService {
  BiometricLoginService._();

  static const String noFaceTemplateMessage =
      'Face sign-in needs a face registered on this server. Sign in with your '
      'password and register your face first.';
  static const String faceNotLinkedMessage =
      'Face sign-in is not linked on this device yet. Sign in with your '
      'password once to link it, then try again.';
  static const String faceRegistrationUnavailableMessage =
      'Could not check your face registration right now. Please try again.';

  static final BiometricLoginService instance = BiometricLoginService._();

  final BiometricApiService _api = BiometricApiService();
  final AuthService _authService = AuthService();

  bool _running = false;
  bool _cancelled = false;

  bool get isRunning => _running;

  void cancel() {
    if (_running) _cancelled = true;
  }

  Future<BiometricLoginOutcome> loginWithFingerprint() async {
    if (_running) {
      return const BiometricLoginOutcome.failure(
        'A biometric sign-in is already in progress.',
      );
    }
    _running = true;
    _cancelled = false;

    try {
      final auth = BiometricAuthService.instance;
      if (!auth.hasCredential) {
        return const BiometricLoginOutcome.failure(
          'Fingerprint sign-in is not set up on this device. Sign in with your '
          'password and enroll your fingerprint in Profile → Biometrics.',
        );
      }

      final availability = await auth.availability();
      if (!availability.available) {
        return BiometricLoginOutcome.failure(availability.reason);
      }

      final signed = await auth.signChallenge(purpose: 'login');
      if (_cancelled) {
        return const BiometricLoginOutcome.failure(
          'Fingerprint sign-in cancelled.',
        );
      }
      if (!signed.success) {
        return BiometricLoginOutcome.failure(signed.message);
      }

      final response = await _api.biometricLogin(
        credentialId: signed.credentialId!,
        nonce: signed.nonce!,
        signature: signed.signature!,
      );

      if (response == null) {
        return const BiometricLoginOutcome.failure(
          'Could not reach the server to complete fingerprint sign-in. Check '
          'your connection and try again.',
        );
      }

      if (!response.isSuccess || response.body['success'] != true) {
        return BiometricLoginOutcome.failure(
          response.body['message']?.toString() ??
              'Fingerprint sign-in was rejected. Sign in with your password.',
        );
      }

      final result = await _authService.applyBiometricSession(response.body);
      if (!result.success) {
        return BiometricLoginOutcome.failure(
          result.message ?? 'Fingerprint sign-in failed.',
        );
      }
      return BiometricLoginOutcome.success(
        result.message ?? 'Signed in with fingerprint.',
      );
    } catch (_) {
      return const BiometricLoginOutcome.failure(
        'Fingerprint sign-in failed. Please sign in with your password.',
      );
    } finally {
      _running = false;
    }
  }

  /// Why face sign-in cannot run on this device, or [FaceLoginBlocker.ready].
  ///
  /// The login screen asks before opening the camera, so a user who is missing a
  /// template or a stored token is told immediately instead of after a capture.
  Future<FaceLoginBlocker> faceLoginBlocker(
    FaceRecognitionService faceService,
  ) async {
    final storedToken = await _authService.readFaceLoginToken();
    return _ensureFaceTemplate(faceService, storedToken);
  }

  Future<BiometricLoginOutcome> loginWithFace(
    FaceRecognitionService faceService, {
    File? matchedPhoto,
    Position? position,
  }) async {
    if (_running) {
      return const BiometricLoginOutcome.failure(
        'A biometric sign-in is already in progress.',
      );
    }
    _running = true;
    _cancelled = false;

    try {
      // The login screen has no session, so memory is empty on a cold start.
      // The template is recovered from the device copy, and from the server via
      // the stored token when that copy is missing — checking only memory is
      // what made face sign-in fail every time.
      final storedToken = await _authService.readFaceLoginToken();
      final template = await _ensureFaceTemplate(faceService, storedToken);
      if (template == FaceLoginBlocker.noTemplate) {
        return const BiometricLoginOutcome.failure(noFaceTemplateMessage);
      }
      if (template == FaceLoginBlocker.notLinked) {
        return const BiometricLoginOutcome.failure(faceNotLinkedMessage);
      }
      if (template == FaceLoginBlocker.serverUnavailable) {
        return const BiometricLoginOutcome.failure(
          faceRegistrationUnavailableMessage,
        );
      }

      // The device-bound credential is what mints the session; the legacy token
      // is only kept for enroling this one.
      final credential = await _authService.readFaceLoginCredential() ??
          await _authService.ensureFaceLoginCredential();
      if (credential == null) {
        return const BiometricLoginOutcome.failure(faceNotLinkedMessage);
      }

      try {
        await faceService.initialize();
      } catch (_) {
        return const BiometricLoginOutcome.failure(
          'The face engine could not start. Please sign in with your password.',
        );
      }

      // [matchedPhoto] is set when the caller already captured and verified the
      // face in-app (see FaceLoginCaptureScreen). The capture has to live outside
      // this method because the transaction overlay covers every route, so a
      // camera screen opened from inside it would be hidden behind the barrier.
      //
      // There is deliberately no fallback capture here: the only other way to
      // reach a camera from this point was the platform intent, which is what
      // silently failed on Android 11+ and made face sign-in look broken.
      final File? photo = matchedPhoto;
      if (photo == null) {
        return const BiometricLoginOutcome.failure('Face sign-in cancelled.');
      }

      final session = await _api.loginWithFaceCredential(
        credentialId: credential.credentialId,
        secret: credential.secret,
        deviceIdentifier: (await DeviceIdentityService().getDeviceMetadata())[
            'deviceIdentifier'],
        latitude: position?.latitude,
        longitude: position?.longitude,
        accuracyMeters: position?.accuracy,
      );
      if (session == null) {
        return const BiometricLoginOutcome.failure(
          'Face verified, but this device is not authorised for face sign-in. '
          'Sign in with your password to re-link it.',
        );
      }

      final applied = await _authService.applyBiometricSession(session);
      if (!applied.success) {
        return BiometricLoginOutcome.failure(
          applied.message ?? 'Face sign-in failed.',
        );
      }
      // The session now owns the token, so the consumed photo is not kept.
      try {
        await photo.delete();
      } catch (_) {}
      return const BiometricLoginOutcome.success('Signed in with face.');
    } catch (_) {
      return const BiometricLoginOutcome.failure(
        'Face sign-in failed. Please sign in with your password.',
      );
    } finally {
      _running = false;
    }
  }

  /// A usable face template, taking one from the server when the device has none.
  ///
  /// The device copy is the normal source, but it is only an optimisation: the
  /// server is authoritative and the stored sign-in token is enough to read it.
  /// Without this, a wiped device copy left every phone unable to sign in with a
  /// face it had clearly registered.
  Future<FaceLoginBlocker> _ensureFaceTemplate(
    FaceRecognitionService faceService,
    String? storedToken,
  ) async {
    final hasTemplate = await faceService.restorePersistedRegistration();
    if (hasTemplate) return FaceLoginBlocker.ready;

    var token = storedToken;
    var refreshed = false;
    if (token == null || token.isEmpty) {
      token = await _refreshFaceLoginToken();
      refreshed = true;
      if (token == null) return FaceLoginBlocker.notLinked;
    }
    final activeToken = token;

    var fetch = await _fetchFaceRegistration(activeToken);
    if (fetch.status == _FaceRegistrationStatus.unauthorized && !refreshed) {
      final freshToken = await _refreshFaceLoginToken();
      if (freshToken == null) return FaceLoginBlocker.notLinked;
      fetch = await _fetchFaceRegistration(freshToken);
    }

    switch (fetch.status) {
      case _FaceRegistrationStatus.found:
        faceService.hydrateRegistration(fetch.registration);
        return await faceService.isFaceRegistered()
            ? FaceLoginBlocker.ready
            : FaceLoginBlocker.noTemplate;
      case _FaceRegistrationStatus.missing:
        return FaceLoginBlocker.noTemplate;
      case _FaceRegistrationStatus.unauthorized:
        return FaceLoginBlocker.notLinked;
      case _FaceRegistrationStatus.unavailable:
        return FaceLoginBlocker.serverUnavailable;
    }
  }

  Future<String?> _refreshFaceLoginToken() async {
    try {
      final credential = await _authService.readFaceLoginCredential();
      if (credential == null) return null;
      final session = await _api.loginWithFaceCredential(
        credentialId: credential.credentialId,
        secret: credential.secret,
        deviceIdentifier: (await DeviceIdentityService().getDeviceMetadata())[
            'deviceIdentifier'],
      );
      final token = session?['token']?.toString();
      if (token == null || token.isEmpty) return null;
      await _authService.storeFaceLoginToken(token);
      return token;
    } catch (_) {
      return null;
    }
  }

  /// `GET face.registration.get` with the stored sign-in token.
  Future<_FaceRegistrationFetch> _fetchFaceRegistration(String token) async {
    final url = await EndpointConfigService.instance.resolveUrl(
          'face.registration.get',
        ) ??
        '${AppConfig.backendApiBaseUrl}/api/v1/mobile/face-registration';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
          'User-Agent': 'PPHLAttendance/2.5 (Android; Flutter)',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 401 || response.statusCode == 403) {
        return const _FaceRegistrationFetch(
          _FaceRegistrationStatus.unauthorized,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const _FaceRegistrationFetch(_FaceRegistrationStatus.unavailable);
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const _FaceRegistrationFetch(_FaceRegistrationStatus.unavailable);
      }
      if (decoded['success'] == false) {
        final message = decoded['message']?.toString();
        final lower = message?.toLowerCase() ?? '';
        final authFailure = UserFacingError.looksLikeCredentialError(message) ||
            lower.contains('token') ||
            lower.contains('expired');
        return _FaceRegistrationFetch(
          authFailure
              ? _FaceRegistrationStatus.unauthorized
              : _FaceRegistrationStatus.missing,
        );
      }

      final data = decoded['data'] is Map ? decoded['data'] as Map : null;
      final raw = decoded['face_registration'] ??
          decoded['faceRegistration'] ??
          data?['face_registration'] ??
          data?['faceRegistration'];
      final registration = FaceRegistrationData.fromJson(raw, expectedSize: null) ??
          FaceRegistrationData.fromJson(data, expectedSize: null);
      if (registration == null) {
        return const _FaceRegistrationFetch(_FaceRegistrationStatus.missing);
      }
      return _FaceRegistrationFetch(
        _FaceRegistrationStatus.found,
        registration,
      );
    } catch (_) {
      return const _FaceRegistrationFetch(_FaceRegistrationStatus.unavailable);
    }
  }
}
