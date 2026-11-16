import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/face_registration_data.dart';
import 'auth_service.dart';
import 'biometric_api_service.dart';
import 'biometric_auth_service.dart';
import 'endpoint_config_service.dart';
import 'face_recognition_service.dart';

enum BiometricLoginMethod { fingerprint, face }

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

  /// Why face sign-in cannot run on this device, or null when it can.
  ///
  /// The login screen asks before opening the camera, so a user who is missing a
  /// template or a stored token is told immediately instead of after a capture.
  Future<String?> faceLoginBlocker(FaceRecognitionService faceService) async {
    final storedToken = await _authService.readFaceLoginToken();
    final hasTemplate = await _ensureFaceTemplate(faceService, storedToken);

    if (!hasTemplate) {
      return 'Face sign-in needs a face registered on this server. Sign in with '
          'your password and register your face first.';
    }
    if (storedToken == null || storedToken.isEmpty) {
      return 'Face sign-in is not set up on this device. Sign in with your '
          'password once with Face login enabled in Profile → Biometrics.';
    }
    return null;
  }

  Future<BiometricLoginOutcome> loginWithFace(
    FaceRecognitionService faceService, {
    File? matchedPhoto,
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
      if (!await _ensureFaceTemplate(faceService, storedToken)) {
        return const BiometricLoginOutcome.failure(
          'Face sign-in needs a face registered on this server. Sign in with '
          'your password and register your face first.',
        );
      }

      if (storedToken == null || storedToken.isEmpty) {
        return const BiometricLoginOutcome.failure(
          'Face sign-in is not set up on this device. Sign in with your '
          'password once with Face login enabled in Profile → Biometrics.',
        );
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

      final session = await _refreshSession(storedToken);
      if (session == null) {
        return const BiometricLoginOutcome.failure(
          'Face verified, but the session could not be renewed. Sign in with '
          'your password.',
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
  Future<bool> _ensureFaceTemplate(
    FaceRecognitionService faceService,
    String? storedToken,
  ) async {
    if (await faceService.restorePersistedRegistration()) return true;
    if (storedToken == null || storedToken.isEmpty) return false;

    final registration = await _fetchFaceRegistration(storedToken);
    if (registration == null) return false;

    faceService.hydrateRegistration(registration);
    return faceService.isFaceRegistered();
  }

  /// `GET /api/v1/mobile/face-registration` with the stored sign-in token.
  Future<FaceRegistrationData?> _fetchFaceRegistration(String token) async {
    final base = await EndpointConfigService.instance.resolveUrl('auth.refresh');
    final origin = base != null && base.isNotEmpty
        ? base.substring(0, base.indexOf('/api/') < 0 ? base.length : base.indexOf('/api/'))
        : AppConfig.backendApiBaseUrl;
    final url = '$origin/api/v1/mobile/face-registration';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
          'User-Agent': 'PPHLAttendance/2.5 (Android; Flutter)',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode < 200 || response.statusCode >= 300) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['success'] == false) return null;

      final raw = decoded['face_registration'] ??
          decoded['faceRegistration'] ??
          (decoded['data'] is Map ? (decoded['data'] as Map)['face_registration'] : null);
      return FaceRegistrationData.fromJson(raw, expectedSize: null);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _refreshSession(String storedToken) async {
    final url = await EndpointConfigService.instance.resolveUrl('auth.refresh') ??
        '${AppConfig.backendApiBaseUrl}/api/v1/refresh';

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $storedToken',
              'User-Agent': 'PPHLAttendance/2.5 (Android; Flutter)',
            },
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['success'] == false) return null;
      final token = decoded['token']?.toString();
      if (token == null || token.isEmpty) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }
}
