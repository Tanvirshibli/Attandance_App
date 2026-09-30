import 'package:employee_attendance/screens/attendance_report_screen.dart';
import 'package:employee_attendance/screens/marketing/marketing_hub_screen.dart';
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
  testWidgets('MarketingHubScreen builds its tabs without throwing', (tester) async {
    await usePhoneViewport(tester);
    SharedPreferences.setMockInitialValues({});

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
}
