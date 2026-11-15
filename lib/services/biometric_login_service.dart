import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../config/app_config.dart';
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

  static const int _faceAttempts = 3;

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

  Future<BiometricLoginOutcome> loginWithFace(
    FaceRecognitionService faceService,
  ) async {
    if (_running) {
      return const BiometricLoginOutcome.failure(
        'A biometric sign-in is already in progress.',
      );
    }
    _running = true;
    _cancelled = false;

    try {
      // The login screen has no session, so memory is empty on a cold start:
      // the template must come from the persisted copy before deciding that
      // this device has no face. Checking memory alone is what made face
      // sign-in fail every time.
      await faceService.restorePersistedRegistration();
      if (!await faceService.hasStoredFace()) {
        return const BiometricLoginOutcome.failure(
          'Face sign-in needs a face registered on this server. Sign in with '
          'your password and register your face first.',
        );
      }

      final storedToken = await _authService.readFaceLoginToken();
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

      String failureMessage =
          'Your face did not match closely enough. Try again in better light, '
          'or sign in with your password.';

      for (var attempt = 0; attempt < _faceAttempts; attempt++) {
        if (_cancelled) {
          return const BiometricLoginOutcome.failure('Face sign-in cancelled.');
        }

        final photo = await _captureFacePhoto();
        if (photo == null) {
          if (_cancelled) {
            return const BiometricLoginOutcome.failure(
              'Face sign-in cancelled.',
            );
          }
          return const BiometricLoginOutcome.failure(
            'No photo was captured. Face sign-in cancelled.',
          );
        }

        final verification = await faceService.verifyFace(photo);
        try {
          await photo.delete();
        } catch (_) {}

        if (!verification.isMatch) {
          failureMessage = verification.message;
          continue;
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
        return const BiometricLoginOutcome.success('Signed in with face.');
      }

      return BiometricLoginOutcome.failure(failureMessage);
    } catch (_) {
      return const BiometricLoginOutcome.failure(
        'Face sign-in failed. Please sign in with your password.',
      );
    } finally {
      _running = false;
    }
  }

  /// One front-camera frame. The template comparison, quality gates and
  /// liveness checks all live in [FaceRecognitionService.verifyFace], so this is
  /// the same strong threshold the check-in flow uses.
  Future<File?> _captureFacePhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 100,
      );
      if (picked == null) return null;
      return File(picked.path);
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
