import 'dart:async';
import 'dart:io';

/// Maps technical/backend failures to short, user-friendly messages.
///
/// Field users should never see stack traces, URLs, or backend jargon in a
/// toast. Keep the mapping conservative: when in doubt, return a generic
/// "something went wrong" message rather than raw server text.
class UserFacingError {
  UserFacingError._();

  static const String wrongCredentials = 'The provided credentials are wrong.';
  static const String noInternet =
      'No internet connection. Please check your network and try again.';
  static const String serverDown =
      'Server is unreachable. Please try again later.';
  static const String tooManyAttempts =
      'Too many attempts. Please wait a moment and try again.';
  static const String generic = 'Something went wrong. Please try again.';

  /// Whether [raw] looks like a credential rejection (401/403/400 auth
  /// failures, Laravel "credentials" messages, etc.).
  static bool looksLikeCredentialError(String? raw) {
    if (raw == null) return false;
    final v = raw.toLowerCase();
    return v.contains('credential') ||
        v.contains('invalid email or password') ||
        v.contains('incorrect password') ||
        v.contains('unauthorized') ||
        v.contains('unauthenticated') ||
        v.contains('authentication failed') ||
        v.contains('login failed') ||
        v.contains('invalid login');
  }

  /// Friendly message for a failed login attempt.
  static String forLogin({int? statusCode, String? rawMessage}) {
    if (statusCode == 429) return tooManyAttempts;
    if (statusCode == 401 || statusCode == 403 || statusCode == 400) {
      return wrongCredentials;
    }
    if (looksLikeCredentialError(rawMessage)) return wrongCredentials;
    if (rawMessage != null &&
        (rawMessage.toLowerCase().contains('validation') ||
            rawMessage.toLowerCase().contains('required'))) {
      return 'Please check your email and password format.';
    }
    if (statusCode != null && statusCode >= 500) return serverDown;
    return generic;
  }

  /// Friendly message for a thrown network error.
  static String forException(Object error) {
    if (error is TimeoutException) return noInternet;
    if (error is SocketException) return noInternet;
    if (error is HandshakeException) return serverDown;
    return generic;
  }

  /// Friendly message for a failed HTTP submit (forms, uploads, punches).
  /// Keeps short, safe server messages (e.g. "Photo is required") but hides
  /// URLs, stack fragments and HTTP jargon.
  static String forSubmit({int? statusCode, String? rawMessage}) {
    if (statusCode == 401 || statusCode == 403) {
      return 'You are not allowed to do that. Please login again.';
    }
    if (statusCode == 429) return tooManyAttempts;
    if (statusCode != null && statusCode >= 500) return serverDown;
    if (rawMessage != null) {
      final v = rawMessage.toLowerCase();
      if (v.contains('required') ||
          v.contains('invalid') ||
          v.contains('validation')) {
        // Validation text is usually short and safe to show.
        return rawMessage;
      }
    }
    return generic;
  }
}
