import 'dart:convert';

import 'package:employee_attendance/models/app_permissions.dart';
import 'package:employee_attendance/models/auth_user_profile.dart';
import 'package:employee_attendance/services/permission_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Must match `_snapshotKey` in `permission_service.dart`, which is private to
/// its library.
const String _snapshotKey = 'permission_snapshot_v1';

/// A profile carrying [permissions], with everything else neutral.
AuthUserProfile _profileWith(
  List<String> permissions, {
  Object? isAdmin,
  Object? isSuperAdmin,
}) {
  // The admin flags are absent by default so the common case needs no
  // conditionals; tests that exercise bypass pass them explicitly.
  final payload = <String, dynamic>{
    'name': 'Test User',
    'email': 'test@example.com',
    'permissions': permissions,
  };
  if (isAdmin != null) {
    payload['isAdmin'] = isAdmin;
  }
  if (isSuperAdmin != null) {
    payload['isSuperAdmin'] = isSuperAdmin;
  }
  return AuthUserProfile.fromJson(payload);
}

void main() {
  // The service is a singleton and SharedPreferences keeps its store in a
  // static, so each test starts from a clean in-memory state and empty storage.
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await PermissionService.instance.clear();
  });
  tearDown(() async {
    await PermissionService.instance.clear();
  });

  group('PermissionService — persisted snapshot', () {
    test('update persists a snapshot that rehydrates the grants', () async {
      await PermissionService.instance
          .update(_profileWith([AppPermissions.trackingRead]));

      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString(_snapshotKey);
      expect(
        saved,
        isNotNull,
        reason: 'update() must persist a snapshot for background isolates',
      );

      await PermissionService.instance.clear();
      expect(preferences.getString(_snapshotKey), isNull);
      expect(PermissionService.instance.isLoaded, isFalse);
      expect(PermissionService.instance.canViewModule('tracking'), isFalse);

      // clear() removes the snapshot so a signed-out device cannot re-hydrate
      // the old grants; restore the exact value the UI isolate had written,
      // which also pins that the writer and the reader agree on the format.
      await preferences.setString(_snapshotKey, saved!);

      expect(await PermissionService.instance.hydrateFromStorage(), isTrue);
      expect(PermissionService.instance.canViewModule('tracking'), isTrue);
    });

    test('admin flags survive the snapshot round trip', () async {
      await PermissionService.instance
          .update(_profileWith(const [], isAdmin: '1'));

      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString(_snapshotKey);
      expect(saved, isNotNull);

      await PermissionService.instance.clear();
      expect(PermissionService.instance.isAdminBypass, isFalse);

      await preferences.setString(_snapshotKey, saved!);

      expect(await PermissionService.instance.hydrateFromStorage(), isTrue);
      expect(PermissionService.instance.isAdminBypass, isTrue);
    });

    test('with no snapshot, hydrateFromStorage fails closed', () async {
      expect(await PermissionService.instance.hydrateFromStorage(), isFalse);
      expect(PermissionService.instance.isLoaded, isFalse);
      expect(PermissionService.instance.canViewModule('tracking'), isFalse);
    });

    test('a corrupt snapshot fails closed', () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_snapshotKey, '{not valid json');

      expect(await PermissionService.instance.hydrateFromStorage(), isFalse);
      expect(PermissionService.instance.isLoaded, isFalse);
      expect(PermissionService.instance.canViewModule('tracking'), isFalse);
    });

    test('clear removes a stale snapshot even with no in-memory state',
        () async {
      // A fresh process can hold no state while a previous session's snapshot
      // is still on disk. Logout must still remove it, or a background isolate
      // could re-hydrate the signed-out grants.
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _snapshotKey,
        jsonEncode(<String, Object>{
          'granted': <String>[AppPermissions.trackingRead],
          'is_admin': false,
          'is_super_admin': false,
        }),
      );

      await PermissionService.instance.clear();

      expect(preferences.getString(_snapshotKey), isNull);
      expect(await PermissionService.instance.hydrateFromStorage(), isFalse);
      expect(PermissionService.instance.canViewModule('tracking'), isFalse);
    });
  });
}
