import 'package:employee_attendance/models/app_permissions.dart';
import 'package:employee_attendance/models/auth_user_profile.dart';
import 'package:employee_attendance/screens/employee_services_hub_screen.dart';
import 'package:employee_attendance/services/permission_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget-level coverage for permission gating in the services hub.
///
/// This file replaces the original `App smoke test`, which asserted
/// `find.text('AttendEase')` and `find.text('Sign In')`. Neither string exists
/// in the app any more — `main.dart` sets `title: 'PPHL Attendance System'` and
/// the login screen only renders after `AppBootstrap` resolves its network
/// branch — so that test had been failing and was documenting a UI from a
/// previous version. Rather than delete the file, this asserts the behaviour
/// that now decides which tiles a user sees, which is the part of the shell a
/// smoke test should actually cover.
void main() {
  // PermissionService is a singleton; each test starts from a clean grant list.
  setUp(PermissionService.instance.clear);
  tearDown(PermissionService.instance.clear);

  void grant(List<String> permissions) {
    PermissionService.instance.update(
      AuthUserProfile.fromJson(<String, dynamic>{
        'name': 'Test User',
        'email': 'test@example.com',
        'permissions': permissions,
      }),
    );
  }

  /// A realistic handset viewport.
  ///
  /// The default 800x600 test surface is *wider but shorter* than a phone, and
  /// the services grid is `SliverGrid`, which lazily builds only what fits. On
  /// the default surface the ungated tiles fill the first rows and a granted
  /// fifth module lands off-screen and is never laid out — so
  /// `find.text('Vehicles')` returns nothing even though the tile is correctly
  /// visible. A tall handset surface makes the whole grid build, which is also
  /// what a real user sees.
  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpHub(WidgetTester tester) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(
      const MaterialApp(home: EmployeeServicesHubScreen()),
    );
    // The tiles animate in with FadeInUp, which leaves a timer pending and
    // fails teardown with "A Timer is still pending even after the widget tree
    // was disposed" — an artefact of the animation, not of the gating. Let it
    // finish so the assertions run against a settled tree.
    await tester.pumpAndSettle();
  }

  /// Grants [permissions] and settles, for a permission change that arrives
  /// after the first build.
  ///
  /// Fixed pumps rather than `pumpAndSettle`: the grids under the tiles show a
  /// shimmer placeholder while loading, which schedules frames indefinitely, so
  /// settling would time out on a correctly-behaving screen. The extra pump at
  /// the end drains the `FadeInUp` stagger the new tiles start on, which is
  /// what would otherwise leave a timer pending at teardown.
  Future<void> grantAndSettle(WidgetTester tester, List<String> permissions) async {
    grant(permissions);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
  }

  group('EmployeeServicesHubScreen — ungated modules', () {
    testWidgets('always shows the employee\'s own records', (tester) async {
      await pumpHub(tester);

      // Attendance, Leave and Payments are not permission-gated, so they must
      // render even before a profile has landed. Otherwise a slow get-my-info
      // would leave the hub looking empty.
      expect(find.text('Attendance report'), findsOneWidget);
      expect(find.text('Leave'), findsOneWidget);
      expect(find.text('Payments'), findsOneWidget);
      expect(find.text('Sales info'), findsOneWidget);
    });
  });

  group('EmployeeServicesHubScreen — gated modules', () {
    testWidgets('hides every gated tile before the profile lands',
        (tester) async {
      // Fail closed: between the first frame and the background profile
      // landing, a gated module must not flash into view and then vanish.
      await pumpHub(tester);

      expect(find.text('HR benefits'), findsNothing);
      expect(find.text('Vehicles'), findsNothing);
      expect(find.text('Farms & dealers'), findsNothing);
      expect(find.text('Geo tracking'), findsNothing);
    });

    testWidgets('hides gated tiles for a user with no permissions',
        (tester) async {
      grant(const []);
      await pumpHub(tester);

      expect(find.text('HR benefits'), findsNothing);
      expect(find.text('Vehicles'), findsNothing);
      expect(find.text('Farms & dealers'), findsNothing);
      expect(find.text('Geo tracking'), findsNothing);
    });

    testWidgets('shows a module once its read permission is granted',
        (tester) async {
      grant(const [AppPermissions.vehiclesRead]);
      await pumpHub(tester);

      expect(find.text('Vehicles'), findsOneWidget);
      // The others are still absent — one grant does not unlock the rest.
      expect(find.text('HR benefits'), findsNothing);
      expect(find.text('Geo tracking'), findsNothing);
    });

    testWidgets('markets.read alone surfaces Farms & dealers', (tester) async {
      // The hub takes any-of its three record permissions, so a markets-only
      // officer reaches the hub and sees only the Markets tab inside it.
      grant(const [AppPermissions.marketsRead]);
      await pumpHub(tester);

      expect(find.text('Farms & dealers'), findsOneWidget);
    });

    testWidgets('a user with unrelated permissions still sees nothing gated',
        (tester) async {
      grant(const [AppPermissions.liveBirdOrderRead]);
      await pumpHub(tester);

      expect(find.text('Vehicles'), findsNothing);
      expect(find.text('HR benefits'), findsNothing);
      expect(find.text('Farms & dealers'), findsNothing);
      expect(find.text('Geo tracking'), findsNothing);
    });
  });

  group('EmployeeServicesHubScreen — admin bypass', () {
    testWidgets('isAdmin "1" reveals every gated tile', (tester) async {
      PermissionService.instance.update(
        AuthUserProfile.fromJson(<String, dynamic>{
          'name': 'Admin',
          'email': 'admin@example.com',
          'permissions': <String>[],
          'isAdmin': '1',
        }),
      );
      await pumpHub(tester);

      expect(find.text('HR benefits'), findsOneWidget);
      expect(find.text('Vehicles'), findsOneWidget);
      expect(find.text('Farms & dealers'), findsOneWidget);
      expect(find.text('Geo tracking'), findsOneWidget);
    });

    testWidgets('isAdmin "0" reveals nothing', (tester) async {
      // The flag arrives as a string from pphl_erp; "0" must not be read as
      // truthy or every employee would silently get full access.
      PermissionService.instance.update(
        AuthUserProfile.fromJson(<String, dynamic>{
          'name': 'Not Admin',
          'email': 'plain@example.com',
          'permissions': <String>[],
          'isAdmin': '0',
        }),
      );
      await pumpHub(tester);

      expect(find.text('Vehicles'), findsNothing);
      expect(find.text('Farms & dealers'), findsNothing);
    });
  });

  group('EmployeeServicesHubScreen — live update', () {
    testWidgets('a tile appears when permissions land after the first build',
        (tester) async {
      await pumpHub(tester);
      expect(find.text('Vehicles'), findsNothing);

      // The permission list arrives with the background profile fetch, after
      // the shell has already rendered. The hub listens, so the user does not
      // have to navigate away and back to see their modules.
      await grantAndSettle(tester, const [AppPermissions.vehiclesRead]);

      expect(find.text('Vehicles'), findsOneWidget);
    });
  });
}
