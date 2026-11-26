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

  /// A timeout is not the same as being offline. The production backend has
  /// been measured taking ~20s to complete a TCP connect while perfectly
  /// healthy, so this wording tells the user to retry rather than to go and
  /// debug working Wi-Fi.
  static const String serverSlow =
      'The server is taking too long to respond. Please try again.';

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
  ///
  /// A timeout is deliberately not mapped to [noInternet]: the backend has
  /// been measured taking ~20s to complete a TCP connect while perfectly
  /// healthy, so a timeout means "slow server" and the user's network is
  /// almost certainly fine. A `SocketException` (host unreachable, DNS
  /// failure) is a real network problem and still says so.
  static String forException(Object error) {
    if (error is TimeoutException) return serverSlow;
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

  /// The server's documented punch refusals, keyed by the reason it returns.
  ///
  /// These arrive as a 4xx with a machine code in `message`. Letting them fall
  /// through to [generic] is what made a face or fingerprint refusal look like
  /// a broken deployment, so each one names the thing the employee can act on.
  static const Map<String, String> _punchRefusals = {
    'gps_required':
        'Location is required to punch. Turn on GPS and try again.',
    'gps_untrusted':
        'Your location looks fake or too far from the office. Move to an open spot and try again.',
    'client_time_required':
        'Your phone time is needed to punch. Enable automatic date and time and try again.',
    'device_time_untrusted':
        'Your phone clock is wrong, so the punch was refused. Turn on automatic date and time.',
    'app_outdated':
        'This version of the app is too old to punch. Please update it.',
    'biometric_authorization_required':
        'This punch needs a fresh face or fingerprint check. Please verify again.',
  };

  /// Friendly message for a refused punch that names the real reason.
  ///
  /// A shift-window refusal is prose the backend wrote for the employee (it
  /// names the shift, the anchor time and the grace deadline), so it is passed
  /// through rather than replaced.
  static String forPunchRefusal({int? statusCode, String? rawMessage}) {
    final raw = rawMessage?.trim();
    if (raw != null && raw.isNotEmpty) {
      final mapped = _punchRefusals[raw.toLowerCase()];
      if (mapped != null) return mapped;

      // The shift-window refusals are full sentences the employee can act on.
      final v = raw.toLowerCase();
      if (v.contains('shift') || v.contains('grace period')) {
        return raw;
      }
    }

    return forSubmit(statusCode: statusCode, rawMessage: raw);
  }
}

/// A failed submit, with the one distinction a caller has to act on: is this an
/// outage worth retrying elsewhere, or the server's decision about the request?
class UserFacingFailure {
  const UserFacingFailure({required this.message, required this.isOutage});

  final String message;

  /// True for a 5xx or a transport failure — something a different host might
  /// still serve. False for a 4xx, which is a decision about this request and
  /// must be shown, not retried.
  final bool isOutage;

  factory UserFacingFailure.fromSubmit({
    int? statusCode,
    String? rawMessage,
  }) {
    return UserFacingFailure(
      message: UserFacingError.forPunchRefusal(
        statusCode: statusCode,
        rawMessage: rawMessage,
      ),
      isOutage: statusCode != null && statusCode >= 500,
    );
  }
}
