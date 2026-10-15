import 'dart:convert';

import 'package:employee_attendance/services/endpoint_config_service.dart';
import 'package:employee_attendance/services/fcm_wake_handler.dart';
import 'package:employee_attendance/services/geo_tracking_service.dart';
import 'package:employee_attendance/services/permission_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Guards the closed-app geo capture path.
///
/// The bug this pins: the WorkManager dispatcher and the FCM background
/// handler each run in a **fresh isolate**, where
///
///  * `PermissionService` has never been fed a profile, so the `tracking.read`
///    gate in `GeoTrackingService.isGeoFeatureEnabled()` denied every capture,
///    and
///  * `FcmWakeHandler._configured` is false, because that per-isolate static is
///    only set by `register()` on the UI isolate — so `onWakeRequested()`
///    returned before capturing anything.
///
/// Everything here resolves offline: when a test needs `EndpointConfigService`
/// it seeds the config cache in SharedPreferences, so no HTTP is attempted.
void main() {
  group('FcmWakeHandler.wakeRequestAllowed — the geo_wake truth table', () {
    final now = DateTime(2026, 1, 1, 12, 0, 0);

    test('blocks when Firebase is not configured', () {
      expect(
        FcmWakeHandler.wakeRequestAllowed(
          firebaseConfigured: false,
          trackingEnabled: true,
          pausedUntilMs: 0,
          now: now,
        ),
        isFalse,
      );
    });

    test('blocks when geo tracking is disabled', () {
      expect(
        FcmWakeHandler.wakeRequestAllowed(
          firebaseConfigured: true,
          trackingEnabled: false,
          pausedUntilMs: 0,
          now: now,
        ),
        isFalse,
      );
    });

    test('blocks while the HRM pause window is still open', () {
      expect(
        FcmWakeHandler.wakeRequestAllowed(
          firebaseConfigured: true,
          trackingEnabled: true,
          pausedUntilMs:
              now.add(const Duration(seconds: 30)).millisecondsSinceEpoch,
          now: now,
        ),
        isFalse,
      );
    });

    test('allows a configured, enabled, unpaused wake-up', () {
      expect(
        FcmWakeHandler.wakeRequestAllowed(
          firebaseConfigured: true,
          trackingEnabled: true,
          pausedUntilMs: 0,
          now: now,
        ),
        isTrue,
      );
    });

    test('allows exactly at the pause boundary', () {
      // The worker blocks with `< pausedUntil`; the wake path must not use a
      // stricter comparison, or a wake landing exactly at the boundary would
      // be dropped.
      expect(
        FcmWakeHandler.wakeRequestAllowed(
          firebaseConfigured: true,
          trackingEnabled: true,
          pausedUntilMs: now.millisecondsSinceEpoch,
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('FcmWakeHandler.deregisterForLogout', () {
    test('is a safe no-op when Firebase is not configured', () async {
      // `isConfigured` is false in this isolate, so the call must return
      // without touching Firebase — logout must never throw on this path.
      await FcmWakeHandler.deregisterForLogout(employeeId: 42);
      await FcmWakeHandler.deregisterForLogout(employeeId: 0);
    });
  });

  group('a fresh isolate hydrates before gating geo capture', () {
    setUp(() {
      // The state a freshly-spawned background isolate sees on a device that
      // has not persisted a permission snapshot: nothing.
      SharedPreferences.setMockInitialValues({});
    });

    test('hydrateFromStorage reports no snapshot and the gate stays shut',
        () async {
      final restored = await PermissionService.instance.hydrateFromStorage();

      expect(restored, isFalse, reason: 'no snapshot was ever persisted');
      expect(
        PermissionService.instance.canViewModule('tracking'),
        isFalse,
        reason: 'a missing snapshot must not loosen the gate',
      );
    });

    test('isGeoFeatureEnabled denies when no snapshot is persisted', () async {
      // Seed only the endpoint-config cache that EndpointConfigService reads,
      // so the feature flag is served from SharedPreferences — no HTTP is
      // attempted. The flag itself is ON, so a false below can only come from
      // the permission gate.
      SharedPreferences.setMockInitialValues({
        EndpointConfigService.configCacheKey: jsonEncode({
          'version': 1,
          'bases': <String, dynamic>{'hrm': 'https://hrm.invalid'},
          'endpoints': <String, dynamic>{},
          'features': <String, dynamic>{'geo.tracking.enabled': true},
        }),
      });

      expect(
        await EndpointConfigService.instance
            .isFeatureEnabled('geo.tracking.enabled', defaultValue: true),
        isTrue,
        reason: 'the feature flag is on; only the permission gate can deny',
      );

      expect(await GeoTrackingService().isGeoFeatureEnabled(), isFalse);
    });
  });
}
