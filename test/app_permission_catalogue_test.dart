import 'package:employee_attendance/models/app_permissions.dart';
import 'package:employee_attendance/models/auth_user_profile.dart';
import 'package:employee_attendance/services/permission_service.dart';
import 'package:flutter_test/flutter_test.dart';

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
  // The service is a singleton, so each test must start from a known state.
  setUp(PermissionService.instance.clear);
  tearDown(PermissionService.instance.clear);

  group('AuthUserProfile — permission parsing', () {
    test('reads the flat permission array HRM returns', () {
      final profile = _profileWith([
        AppPermissions.farmsRead,
        AppPermissions.marketsCreate,
      ]);

      expect(profile.permissions, [AppPermissions.farmsRead, AppPermissions.marketsCreate]);
    });

    test('a user with no roles gets an empty list, not null', () {
      // `UserController::getSelf` sends `permissions: []` for an unassigned
      // user. Parsing that must not throw and must not invent grants.
      final profile = AuthUserProfile.fromJson(<String, dynamic>{
        'name': 'No Roles',
        'email': 'noroles@example.com',
      });

      expect(profile.permissions, isEmpty);
    });

    test('deduplicates and drops blanks', () {
      final profile = _profileWith([
        AppPermissions.farmsRead,
        '',
        AppPermissions.farmsRead,
        '   ',
        'null',
      ]);

      expect(profile.permissions, [AppPermissions.farmsRead]);
    });

    test('reads role names from the roles2 eager-load', () {
      // `roles2` is a belongsToMany over user_has_roles, and this hand-rolled
      // schema names the column roleName, not name.
      final profile = AuthUserProfile.fromJson(<String, dynamic>{
        'name': 'Role Holder',
        'email': 'role@example.com',
        'roles2': [
          {'id': 1, 'roleName': 'Zone Officer'},
          {'id': 2, 'roleName': 'Sales Manager'},
        ],
      });

      expect(profile.roles, ['Zone Officer', 'Sales Manager']);
    });

    test('unknown extra keys in the payload are ignored', () {
      final profile = AuthUserProfile.fromJson(<String, dynamic>{
        'name': 'Future Shape',
        'email': 'future@example.com',
        'permissions': [AppPermissions.benefitsRead],
        'someFieldTheAppDoesNotKnow': {'nested': true},
      });

      expect(profile.permissions, [AppPermissions.benefitsRead]);
    });
  });

  group('AuthUserProfile.parseAdminFlag', () {
    // pphl_erp sends these as the strings "1" / "0", and the HRM web client
    // reads them with Boolean(parseInt(...)). "0" must be falsy — getting this
    // wrong hands every employee full access.
    test('"0" is falsy and "1" is truthy, as strings', () {
      expect(AuthUserProfile.parseAdminFlag('0'), isFalse);
      expect(AuthUserProfile.parseAdminFlag('1'), isTrue);
    });

    test('handles real booleans and numbers', () {
      expect(AuthUserProfile.parseAdminFlag(true), isTrue);
      expect(AuthUserProfile.parseAdminFlag(false), isFalse);
      expect(AuthUserProfile.parseAdminFlag(1), isTrue);
      expect(AuthUserProfile.parseAdminFlag(0), isFalse);
    });

    test('treats absent, null and empty as falsy', () {
      expect(AuthUserProfile.parseAdminFlag(null), isFalse);
      expect(AuthUserProfile.parseAdminFlag(''), isFalse);
      expect(AuthUserProfile.parseAdminFlag('null'), isFalse);
    });

    test('"false" is falsy', () {
      expect(AuthUserProfile.parseAdminFlag('false'), isFalse);
    });
  });

  group('PermissionService — failing closed', () {
    test('before the profile lands, nothing gated is visible', () {
      final permissions = PermissionService.instance;

      expect(permissions.isLoaded, isFalse);
      expect(permissions.can(AppPermissions.farmsRead), isFalse);
      expect(permissions.canViewModule('vehicles'), isFalse);
      expect(permissions.canViewModule('benefits'), isFalse);
    });

    test('a fetched-but-empty permission list still denies', () {
      // An empty list is a real answer from the server, distinct from "we have
      // not asked yet". It must not be mistaken for allow-all.
      PermissionService.instance.update(_profileWith(const []));

      expect(PermissionService.instance.isLoaded, isTrue);
      expect(PermissionService.instance.can(AppPermissions.farmsRead), isFalse);
      expect(PermissionService.instance.canViewModule('marketing'), isFalse);
    });

    test('a null profile is ignored rather than revoking a live session', () {
      PermissionService.instance
          .update(_profileWith([AppPermissions.farmsRead]));
      PermissionService.instance.update(null);

      expect(PermissionService.instance.can(AppPermissions.farmsRead), isTrue);
    });
  });

  group('PermissionService — comparisons', () {
    test('is case-insensitive, matching the HRM web client', () {
      PermissionService.instance.update(_profileWith(['FARMS.READ']));

      expect(PermissionService.instance.can(AppPermissions.farmsRead), isTrue);
      expect(PermissionService.instance.can('FaRmS.ReAd'), isTrue);
    });

    test('an unknown permission is simply not granted', () {
      // HRM's catalogue grows at runtime, so a string the app has never seen
      // must be inert rather than an error.
      PermissionService.instance.update(_profileWith(['some.future.permission']));

      expect(PermissionService.instance.can('some.future.permission'), isTrue);
      expect(PermissionService.instance.can(AppPermissions.farmsRead), isFalse);
      expect(PermissionService.instance.canViewModule('marketing'), isFalse);
    });

    test('a null or empty requirement is satisfied', () {
      PermissionService.instance.update(_profileWith(const []));

      expect(PermissionService.instance.can(null), isTrue);
      expect(PermissionService.instance.can(''), isTrue);
      expect(PermissionService.instance.canAny(null), isTrue);
      expect(PermissionService.instance.canAny(const <String>[]), isTrue);
      expect(PermissionService.instance.canAll(const <String>[]), isTrue);
    });

    test('canAny is any-of and canAll is all-of', () {
      PermissionService.instance.update(
        _profileWith([AppPermissions.marketsRead]),
      );

      expect(
        PermissionService.instance.canAny(
          const [AppPermissions.farmsRead, AppPermissions.marketsRead],
        ),
        isTrue,
      );
      expect(
        PermissionService.instance.canAll(
          const [AppPermissions.farmsRead, AppPermissions.marketsRead],
        ),
        isFalse,
      );
    });
  });

  group('PermissionService — admin bypass', () {
    test('isAdmin alone grants every module', () {
      PermissionService.instance.update(_profileWith(const [], isAdmin: '1'));

      expect(PermissionService.instance.canViewModule('marketing'), isTrue);
      expect(PermissionService.instance.canViewModule('vehicles'), isTrue);
      expect(PermissionService.instance.canCreateIn('farm'), isTrue);
    });

    test('isSuperAdmin alone grants every module', () {
      PermissionService.instance
          .update(_profileWith(const [], isSuperAdmin: '1'));

      expect(PermissionService.instance.canViewModule('marketing'), isTrue);
      expect(PermissionService.instance.canCreateIn('market'), isTrue);
    });

    test('isAdmin "0" grants nothing', () {
      PermissionService.instance.update(_profileWith(const [], isAdmin: '0'));

      expect(PermissionService.instance.isAdmin, isFalse);
      expect(PermissionService.instance.canViewModule('marketing'), isFalse);
    });
  });

  group('PermissionService — module visibility', () {
    test('markets.read alone surfaces the marketing hub', () {
      // An officer who may only read markets should see the hub and only the
      // Markets tab inside it.
      PermissionService.instance
          .update(_profileWith([AppPermissions.marketsRead]));

      expect(PermissionService.instance.canViewModule('marketing'), isTrue);
      expect(
        PermissionService.instance.canAny(
          AppPermissions.marketingReadPermissions('market'),
        ),
        isTrue,
      );
      expect(
        PermissionService.instance.canAny(
          AppPermissions.marketingReadPermissions('farm'),
        ),
        isFalse,
      );
    });

    test('holding no marketing permission hides the hub entirely', () {
      PermissionService.instance.update(_profileWith([AppPermissions.benefitsRead]));

      expect(PermissionService.instance.canViewModule('marketing'), isFalse);
    });

    test('ungated modules stay visible with an empty grant list', () {
      // Attendance, Leave and Payments carry the employee's own records.
      PermissionService.instance.update(_profileWith(const []));

      expect(PermissionService.instance.canViewModule('attendance'), isTrue);
      expect(PermissionService.instance.canViewModule('unknown-module'), isTrue);
      expect(PermissionService.instance.canViewModule(null), isTrue);
    });

    test('reading a module does not imply being able to create in it', () {
      PermissionService.instance.update(_profileWith([AppPermissions.farmsRead]));

      expect(PermissionService.instance.canViewModule('marketing'), isTrue);
      expect(PermissionService.instance.canCreateIn('farm'), isFalse);
    });

    test('creating in a module with no create permission is allowed', () {
      // vehicles and tracking are read-only modules in this catalogue.
      PermissionService.instance
          .update(_profileWith([AppPermissions.vehiclesRead]));

      expect(PermissionService.instance.canCreateIn('vehicles'), isTrue);
    });

    test('the read and create maps share one key space', () {
      // `moduleCreatePermissions` is keyed by the marketing tab key ('farm'),
      // not the permission's module name ('farms'). A rename of one map's keys
      // without the other would leave a create button permanently unlocked or
      // permanently locked, and neither shows up until a user tries it — so
      // assert every tab key resolves in both maps.
      for (final key in const ['farm', 'dealer', 'market']) {
        expect(
          AppPermissions.marketingReadPermissions(key),
          isNotNull,
          reason: '$key has no read mapping',
        );
        expect(
          AppPermissions.marketingCreatePermission(key),
          isNotNull,
          reason: '$key has no create mapping',
        );
      }
    });
  });

  group('PermissionService — lifecycle', () {
    test('clear drops grants and resets the loaded flag', () {
      PermissionService.instance
          .update(_profileWith([AppPermissions.farmsRead], isAdmin: '1'));
      expect(PermissionService.instance.can(AppPermissions.farmsRead), isTrue);

      PermissionService.instance.clear();

      expect(PermissionService.instance.isLoaded, isFalse);
      expect(PermissionService.instance.granted, isEmpty);
      expect(PermissionService.instance.isAdminBypass, isFalse);
      expect(PermissionService.instance.can(AppPermissions.farmsRead), isFalse);
    });

    test('clear notifies listeners so open screens re-hide their tiles', () {
      PermissionService.instance
          .update(_profileWith([AppPermissions.farmsRead]));
      var notifications = 0;
      PermissionService.instance.addListener(() => notifications++);

      PermissionService.instance.clear();

      expect(notifications, 1);
    });

    test('an identical update does not notify again', () {
      final profile = _profileWith([AppPermissions.farmsRead]);
      PermissionService.instance.update(profile);
      var notifications = 0;
      PermissionService.instance.addListener(() => notifications++);

      PermissionService.instance.update(profile);

      expect(notifications, 0);
    });

    test('a changed grant set does notify', () {
      PermissionService.instance.update(_profileWith([AppPermissions.farmsRead]));
      var notifications = 0;
      PermissionService.instance.addListener(() => notifications++);

      PermissionService.instance.update(
        _profileWith([AppPermissions.farmsRead, AppPermissions.marketsRead]),
      );

      expect(notifications, 1);
      expect(PermissionService.instance.granted, hasLength(2));
    });
  });

  group('AppPermissions catalogue', () {
    test('contains every permission string from the HRM list', () {
      // The literal strings, not the constants, so a typo in a constant name
      // or a value fails here rather than at runtime against production.
      expect(
        AppPermissions.all,
        containsAll(<String>[
          'prInfo.create',
          'prInfo.read',
          'salesOrder.create',
          'salesOrder.read',
          'liveBirdOrder.create',
          'liveBirdOrder.read',
          'liveBirdOrder.all',
          'liveBirdOrder.live',
          'liveBirdOrder.cull',
          'fertilizerOrder.create',
          'fertilizerOrder.read',
          'chicksBooking.create',
          'chicksBooking.read',
          'feedBooking.create',
          'feedBooking.read',
          'dealer.create',
          'dealer.read',
          'farms.create',
          'farms.read',
          'markets.create',
          'markets.read',
          'vehicles.read',
          'tracking.read',
          'benefits.read',
        ]),
      );
    });

    test('every catalogue entry is unique and well-formed', () {
      expect(AppPermissions.all.toSet().length, AppPermissions.all.length);
      for (final permission in AppPermissions.all) {
        expect(permission, matches(RegExp(r'^[a-zA-Z]+\.[a-zA-Z]+$')));
      }
    });

    test('the denial message names the action and the route to fixing it', () {
      final message =
          PermissionService.instance.denialMessage('farm');

      expect(message, contains('do not have permission'));
      expect(message, contains('farms'));
      expect(message, contains('HR admin'));
    });
  });
}
