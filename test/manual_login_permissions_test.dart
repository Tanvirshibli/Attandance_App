import 'dart:convert';

import 'package:employee_attendance/models/app_permissions.dart';
import 'package:employee_attendance/services/auth_service.dart';
import 'package:employee_attendance/services/permission_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression guard for permissions after a **manual** sign-in.
///
/// The bug this pins: `PermissionService.update()` used to be called only from
/// `AppBootstrap._warmAuthenticatedSession()`, which runs on auto-login.
/// `LoginScreen` fetches the profile from its own `_hydrateProfileInBackground()`
/// instead, so after a manual sign-in nothing ever populated the service. It
/// stayed empty, failed closed, and hid every gated module — until the user
/// closed and reopened the app, at which point auto-login took the other path
/// and the tiles appeared.
///
/// The other permission tests drive `PermissionService.update()` directly,
/// which is exactly why they never caught this: the defect was in *who* calls
/// it. These go through the real `AuthService.getCurrentUserProfile()`.
///
/// Everything resolves offline: with no cached bootstrap URL,
/// `EndpointConfigService` falls back to its compiled-in config, so the only
/// HTTP the service makes is the profile request these tests stub.
void main() {
  setUp(() {
    // A token must exist before a profile is fetched — `getCurrentUserProfile`
    // returns null immediately without one (auth_service.dart:407-410). Seeding
    // it here mirrors the state a real login leaves behind, which is the state
    // the bug occurred in.
    SharedPreferences.setMockInitialValues({'auth_token': 'test-token'});
    PermissionService.instance.clear();
    AuthService.clearProfileCache();
  });

  tearDown(() {
    PermissionService.instance.clear();
    AuthService.clearProfileCache();
  });

  /// A `get-my-info` body carrying [permissions].
  String profileBody(List<String> permissions, {String name = 'Test User'}) {
    return jsonEncode({
      'message': 'User get successfully',
      'user': {
        'name': name,
        'email': 'test@example.com',
        'permissions': permissions,
      },
    });
  }

  group('a manual-login profile fetch populates PermissionService', () {
    test('grants reach the service', () async {
      // The regression itself. On the broken code this fails: the service stays
      // empty, so can(farms.read) is false and every gated tile stays hidden.
      final service =
          serviceServing(() => profileBody([AppPermissions.farmsRead]));

      final profile = await service.getCurrentUserProfile(forceRefresh: true);

      expect(profile, isNotNull);
      expect(profile!.permissions, [AppPermissions.farmsRead]);
      expect(
        PermissionService.instance.can(AppPermissions.farmsRead),
        isTrue,
        reason: 'a manual-login fetch must populate permissions',
      );
      expect(PermissionService.instance.isLoaded, isTrue);
    });

    test('a module becomes visible', () async {
      final service =
          serviceServing(() => profileBody([AppPermissions.marketsRead]));

      await service.getCurrentUserProfile(forceRefresh: true);

      expect(PermissionService.instance.canViewModule('marketing'), isTrue);
      expect(PermissionService.instance.canViewModule('vehicles'), isFalse);
    });

    test('a create permission reaches the service', () async {
      final service = serviceServing(
        () => profileBody(
            [AppPermissions.farmsRead, AppPermissions.farmsCreate]),
      );

      await service.getCurrentUserProfile(forceRefresh: true);

      expect(PermissionService.instance.canCreateIn('farm'), isTrue);
    });
  });

  group('a fetch must not loosen the gate', () {
    test('an empty permission list leaves everything denied', () async {
      // Guards against the fix regressing into allow-all.
      final service = serviceServing(() => profileBody(const []));

      await service.getCurrentUserProfile(forceRefresh: true);

      expect(PermissionService.instance.isLoaded, isTrue);
      expect(PermissionService.instance.can(AppPermissions.farmsRead), isFalse);
      expect(PermissionService.instance.canViewModule('marketing'), isFalse);
    });

    test('an admin flag in the payload still bypasses', () async {
      // The bypass must survive the move: it is parsed from the same profile.
      final body = jsonEncode({
        'message': 'ok',
        'user': {
          'name': 'Admin',
          'email': 'admin@example.com',
          'permissions': <String>[],
          'isAdmin': '1',
        },
      });
      final service = serviceServing(() => body);

      await service.getCurrentUserProfile(forceRefresh: true);

      expect(PermissionService.instance.isAdminBypass, isTrue);
      expect(PermissionService.instance.canViewModule('marketing'), isTrue);
    });

    test('a super admin sees every tile on the very first fetch', () async {
      // The reported scenario, exactly: a super admin whose role carries the
      // permissions *disabled* must still reach every tile. On the broken
      // wiring the bypass flag was never read on a manual sign-in, so the empty
      // service denied every gated module and the admin saw a stripped-down app
      // until they reopened it.
      final body = jsonEncode({
        'message': 'ok',
        'user': {
          'name': 'Super Admin',
          'email': 'root@example.com',
          'permissions': <String>[],
          'isSuperAdmin': '1',
        },
      });
      final service = serviceServing(() => body);

      await service.getCurrentUserProfile(forceRefresh: true);

      expect(PermissionService.instance.isSuperAdmin, isTrue);
      expect(PermissionService.instance.isAdminBypass, isTrue);

      // Every gated module in AppPermissions, checked by reading the catalogue
      // rather than a hand-copied list — so a module added later is covered
      // here automatically instead of silently going untested.
      for (final entry
          in AppPermissions.moduleReadPermissions.entries) {
        expect(
          PermissionService.instance.canViewModule(entry.key),
          isTrue,
          reason: 'super admin must see ${entry.key}',
        );
      }
      for (final key in AppPermissions.moduleCreatePermissions.keys) {
        expect(
          PermissionService.instance.canCreateIn(key),
          isTrue,
          reason: 'super admin must be able to create in $key',
        );
      }
      // Every individual grant too, so the bypass is proven at the leaf.
      for (final permission in AppPermissions.all) {
        expect(
          PermissionService.instance.can(permission),
          isTrue,
          reason: 'super admin must be granted $permission',
        );
      }
    });
  });

  group('a second fetch replaces the previous grants', () {
    test('a different user does not inherit the first user modules', () async {
      // The stale-session case: two sign-ins on one device.
      final bodies = [
        profileBody([AppPermissions.vehiclesRead], name: 'First'),
        profileBody([AppPermissions.farmsRead], name: 'Second'),
      ];
      var index = 0;
      final service = serviceServing(() => bodies[index++]);

      await service.getCurrentUserProfile(forceRefresh: true);
      expect(
        PermissionService.instance.can(AppPermissions.vehiclesRead),
        isTrue,
      );

      await service.getCurrentUserProfile(forceRefresh: true);

      expect(
        PermissionService.instance.can(AppPermissions.vehiclesRead),
        isFalse,
        reason: "the second user's grants must replace the first's",
      );
      expect(PermissionService.instance.can(AppPermissions.farmsRead), isTrue);
    });
  });
}

/// Builds an `AuthService` whose HTTP is answered by [next].
///
/// Uses the injectable `httpClient` seam, the same DI shape the other services
/// use for `HrmApiClient`, so nothing global is patched. [MockClient] ships
/// with the `http` package — no test dependency added.
AuthService serviceServing(String Function() next) {
  return AuthService(
    httpClient: MockClient((request) async {
      // The URL is ignored on purpose: the service sweeps a list of candidate
      // profile URLs, and the stub answers whichever it tries first.
      return http.Response(next(), 200, headers: {
        'content-type': 'application/json; charset=utf-8',
      });
    }),
  );
}
