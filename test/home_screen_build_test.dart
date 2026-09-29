import 'package:employee_attendance/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [HomeScreen] on its own so a build-time exception surfaces as a real
/// test failure with a stack trace, instead of a blank screen in the app.
void main() {
  testWidgets('HomeScreen builds without throwing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen()),
    );

    // One frame is enough to run build(); the screen's data loads are async and
    // are not what we are testing here.
    await tester.pump();

    // Drain the animate_do entrance timers so the teardown does not fail on a
    // pending timer. This is harness noise, not a product defect.
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
