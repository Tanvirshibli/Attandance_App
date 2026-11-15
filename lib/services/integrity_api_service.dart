import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'auth_service.dart';
import 'device_identity_service.dart';
import 'device_integrity_service.dart';
import 'internet_time_service.dart';

/// Reports integrity events to the backend.
///
/// This is telemetry, not enforcement: enforcement already happened on the
/// device (the punch was refused, or the app locked itself). So every failure
/// here — no network, no token, a backend that has not deployed the endpoint
/// yet — is logged and dropped. A report that cannot be sent must never turn
/// into a second, unrelated reason the employee cannot clock in.
///
/// The body carries both clocks on purpose. `clientInternetTime` is what the app
/// believes the real time is, `deviceTime` is what the phone claims, and the gap
/// between them is the evidence for a [IntegrityType.timeDrift] event. Support
/// can then tell "the punch was late" from "the phone's clock was wrong"
/// without asking the employee.
class IntegrityApiService {
  IntegrityApiService({AuthService? authService})
      : _authService = authService ?? AuthService();

  /// One POST per event, tried against every configured base URL in order.
  static const String _path = '/api/v1/mobile/integrity-events';

  /// Short on purpose. This runs in the background and nobody is waiting for
  /// it; a slow host must not hold a socket open for the length of a punch.
  static const Duration _timeout = Duration(seconds: 12);

  final AuthService _authService;
  final DeviceIdentityService _deviceIdentity = DeviceIdentityService();

  /// Sends one violation. Returns true when a candidate host accepted it.
  ///
  /// Never throws, and never awaited by anything on the punch path.
  Future<bool> report(IntegrityViolation violation) async {
    try {
      final body = await _buildBody(violation);
      final payload = jsonEncode(body);

      final token = await _authService.getToken();
      final headers = <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        // Same UA the login path sends, so a WAF that rules the app's traffic in
        // does not drop this one.
        'User-Agent': 'PPHLAttendance/2.5 (Android; Flutter)',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      for (final base in AppConfig.authApiBaseUrlCandidates) {
        final trimmed = base.trim();
        if (trimmed.isEmpty) continue;

        try {
          final response = await http
              .post(Uri.parse('$trimmed$_path'), headers: headers, body: payload)
              .timeout(_timeout);

          if (response.statusCode == 404) {
            // This host does not serve the endpoint: try the next candidate
            // rather than reporting a failure that says nothing about the event.
            continue;
          }

          if (response.statusCode >= 200 && response.statusCode < 300) {
            return true;
          }

          debugPrint(
            'IntegrityApiService: $trimmed returned ${response.statusCode} for '
            '${violation.wireName}',
          );
          return false;
        } catch (error) {
          debugPrint('IntegrityApiService: $trimmed failed ($error)');
          continue;
        }
      }

      debugPrint(
        'IntegrityApiService: no host accepted ${violation.wireName} '
        '(tried ${AppConfig.authApiBaseUrlCandidates.join(', ')})',
      );
      return false;
    } catch (error) {
      // Identifier lookup, JSON encoding, clock read — any of them can fail, and
      // none of them is worth surfacing.
      debugPrint('IntegrityApiService: could not build the event ($error)');
      return false;
    }
  }

  Future<Map<String, dynamic>> _buildBody(IntegrityViolation violation) async {
    String deviceIdentifier = '';
    String deviceName = '';
    try {
      final metadata = await _deviceIdentity.getDeviceMetadata();
      deviceIdentifier = metadata['deviceIdentifier'] ?? '';
      deviceName = metadata['deviceName'] ?? '';
    } catch (error) {
      debugPrint('IntegrityApiService: no device identity ($error)');
    }

    final internetTime = InternetTimeService.instance;

    return <String, dynamic>{
      'type': violation.wireName,
      'detail': violation.detail,
      'deviceIdentifier': deviceIdentifier,
      'deviceName': deviceName,
      // Null when nothing has synced: the backend must be able to tell "the app
      // has no internet clock" from "the internet clock said 09:12".
      'clientInternetTime':
          internetTime.isSynced ? internetTime.now().toIso8601String() : null,
      'deviceTime': DateTime.now().toIso8601String(),
    };
  }
}
