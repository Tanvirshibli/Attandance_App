import 'package:employee_attendance/models/app_permissions.dart';
import 'package:employee_attendance/models/auth_user_profile.dart';
import 'package:employee_attendance/models/marketing_models.dart';
import 'package:employee_attendance/screens/attendance_report_screen.dart';
import 'package:employee_attendance/screens/marketing/marketing_hub_screen.dart';
import 'package:employee_attendance/screens/marketing/party_detail_screen.dart';
import 'package:employee_attendance/services/permission_service.dart';
import 'package:employee_attendance/widgets/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Build smoke test for the Stage 2 report screen.
///
/// A layout assertion inside a sliver (for example `CrossAxisAlignment.stretch`
/// on a `Row` with unbounded height) takes the whole screen down and renders as
/// a blank page with no useful log output. This fails loudly with a stack trace
/// instead.
///
/// `CheckInScreen` and `GeoTrackingScreen` are deliberately absent: check-in
/// loads the TFLite face model, which has no Windows dylib, and geo opens a
/// Google Map. Neither can be pumped headless, and a test that cannot run is
/// worse than no test — it just adds noise.
void main() {
  Future<void> usePhoneViewport(WidgetTester tester) async {
    // A realistic phone viewport. The default 800x600 test surface is shorter
    // than a real handset and makes the date-range field overflow, which is a
    // harness artifact rather than a product defect.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  testWidgets('AttendanceReportScreen builds without throwing', (tester) async {
    await usePhoneViewport(tester);

    await tester.pumpWidget(const MaterialApp(home: AttendanceReportScreen()));
    await tester.pump();

    // Fixed pumps rather than pumpAndSettle: while the screen is loading it
    // shows a CircularProgressIndicator, which schedules frames forever, so
    // pumpAndSettle would time out even though the layout is fine.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
  });

  testWidgets('AppHeader renders inside a sliver with no error', (tester) async {
    // Regression guard for a blank-geo-tracking screen. The header and cards
    // sit in a CustomScrollView, so a layout assertion anywhere in the tree
    // takes the whole screen down rather than showing an error banner.
    await usePhoneViewport(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: AppHeader(title: 'Geo tracking', subtitle: 'Live map'),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 400)),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Geo tracking'), findsOneWidget);
  });

  // The marketing hub stacks a header, the zone note, a TabBar and a
  // full-height TabBarView of grids, with the tab's actions pinned to a
  // bottom bar. A layout failure anywhere in that chain -- an unbounded
  // height, pills that cannot fit the row, a TabBarView without a controller --
  // blanks the screen with no useful log, so it is worth a guard.
  //
  // The hub gates its tabs behind an async feature check that reads the remote
  // endpoint config, so prefs are mocked and pumped until that resolves.
  //
  // The tabs themselves are additionally permission-gated: with no grants the
  // hub renders its "nothing to show" state and there are no pills to lay out.
  // These are layout guards, so they grant the read and create permissions that
  // put the hub in the fully-populated state they were written to check.
  void grantFullMarketingAccess() {
    PermissionService.instance.update(
      AuthUserProfile.fromJson(<String, dynamic>{
        'name': 'Stage 2 Tester',
        'email': 'stage2@example.com',
        'permissions': <String>[
          AppPermissions.farmsRead,
          AppPermissions.farmsCreate,
          AppPermissions.dealerRead,
          AppPermissions.dealerCreate,
          AppPermissions.marketsRead,
          AppPermissions.marketsCreate,
        ],
      }),
    );
  }

  setUp(PermissionService.instance.clear);
  tearDown(PermissionService.instance.clear);

  testWidgets('MarketingHubScreen builds its tabs without throwing', (tester) async {
    await usePhoneViewport(tester);
    SharedPreferences.setMockInitialValues({});
    grantFullMarketingAccess();

    await tester.pumpWidget(const MaterialApp(home: MarketingHubScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
    // The module card is gone: "Farms" is now only the tab label, and the
    // second heading the old card drew no longer exists.
    expect(find.text('Farms'), findsOneWidget);
    expect(find.text('Dealers'), findsOneWidget);
    expect(find.text('Markets'), findsOneWidget);
    // The pinned bar is what replaced the card's inline action row.
    expect(find.text('Add farm'), findsOneWidget);
    expect(find.text('All farms'), findsOneWidget);
  });

  testWidgets('the marketing hub tabs switch to the dealer module', (tester) async {
    await usePhoneViewport(tester);
    SharedPreferences.setMockInitialValues({});
    grantFullMarketingAccess();

    await tester.pumpWidget(const MaterialApp(home: MarketingHubScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // The farm tab is selected first, so the pinned action bar names it.
    expect(find.text('Add farm'), findsOneWidget);
    expect(find.text('All farms'), findsOneWidget);

    await tester.tap(find.text('Dealers'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('Add dealer'), findsOneWidget);
    expect(find.text('All dealers'), findsOneWidget);
    expect(find.text('Add farm'), findsNothing);
  });

  testWidgets('a markets-only grant shows one tab, not three', (tester) async {
    // Regression guard for the tab/filter pairing. Filtering the tab labels
    // without resizing the TabController renders a third tab the user has no
    // permission for, and indexing the action bar by the filtered list against
    // an unfiltered controller throws on out-of-range.
    await usePhoneViewport(tester);
    SharedPreferences.setMockInitialValues({});
    PermissionService.instance.update(
      AuthUserProfile.fromJson(<String, dynamic>{
        'name': 'Markets Only',
        'email': 'markets@example.com',
        'permissions': <String>[AppPermissions.marketsRead],
      }),
    );

    await tester.pumpWidget(const MaterialApp(home: MarketingHubScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
    expect(find.text('Markets'), findsOneWidget);
    expect(find.text('Farms'), findsNothing);
    expect(find.text('Dealers'), findsNothing);
    // The lone tab's actions are labelled for markets, not for farms.
    expect(find.text('Add market'), findsOneWidget);
    expect(find.text('Add farm'), findsNothing);
  });

  testWidgets('without any marketing grant the hub renders its empty state',
      (tester) async {
    // Failing closed: no grants means no tabs and no create pills, rather than
    // three tabs the user should not have.
    await usePhoneViewport(tester);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MaterialApp(home: MarketingHubScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
    expect(find.text('Farms'), findsNothing);
    expect(find.text('Dealers'), findsNothing);
    expect(find.text('Markets'), findsNothing);
    expect(find.text('Add farm'), findsNothing);
  });

  // The detail page stacks the record card, the action pills, a pinned TabBar
  // and a TabBarView of two independently scrolling lists inside a
  // NestedScrollView. A layout failure anywhere in that chain -- a pinned
  // header that cannot size itself, an overlap injector without its absorber,
  // a tab body that cannot scroll -- blanks the page with no useful log.
  Party dealerParty() => Party.fromJson(<String, dynamic>{
        'id': 1,
        'partyType': 'dealer',
        'name': 'Rahman Poultry',
        'phone': '01712345678',
        'zoneName': 'Dhaka South',
        'status': 'active',
      });

  testWidgets('PartyDetailScreen builds its visits and follow-ups tabs',
      (tester) async {
    await usePhoneViewport(tester);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        home: PartyDetailScreen(partyId: 1, initialParty: dealerParty()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
    expect(find.text('Visits'), findsOneWidget);
    expect(find.text('Follow-ups'), findsOneWidget);
    expect(find.text('Post a visit'), findsOneWidget);
    expect(find.text('New follow-up'), findsOneWidget);

    await tester.tap(find.text('Follow-ups'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
  });
}
