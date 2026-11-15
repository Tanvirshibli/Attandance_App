import 'dart:async';

import 'package:employee_attendance/services/transaction_ui_service.dart';
import 'package:employee_attendance/widgets/transaction_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host() {
  return const MaterialApp(
    home: TransactionOverlay(child: Scaffold(body: Text('home'))),
  );
}

void main() {
  setUp(() => TransactionUiService.instance.reset());
  tearDown(() => TransactionUiService.instance.reset());

  testWidgets('shows a ring, then a tick, then clears after two seconds',
      (tester) async {
    await tester.pumpWidget(_host());

    final completer = Completer<int>();
    final future = TransactionUiService.instance.run(
      () => completer.future,
      label: 'Checking in',
    );

    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Checking in'), findsOneWidget);

    completer.complete(1);
    await future;
    await tester.pump();
    // Let the switcher's cross-fade finish before asserting the ring is gone.
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.byIcon(Icons.check), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('the label sits under a Material so no debug underline is drawn',
      (tester) async {
    await tester.pumpWidget(_host());

    final completer = Completer<int>();
    TransactionUiService.instance.run(
      () => completer.future,
      label: 'Checking in',
    );
    await tester.pump();

    final label = find.text('Checking in');
    expect(label, findsOneWidget);
    expect(
      find.ancestor(of: label, matching: find.byType(Material)),
      findsWidgets,
    );
    expect(
      tester.widget<Text>(label).style?.decoration,
      isNot(TextDecoration.underline),
    );
  });

  testWidgets('a returned failure result shows a cross, not a tick',
      (tester) async {
    await tester.pumpWidget(_host());

    // Biometric sign-in reports failure by returning a result, never by
    // throwing. The overlay must read the verdict, not the absence of an error.
    final result = await TransactionUiService.instance.run<({bool ok})>(
      () async => (ok: false),
      label: 'Verifying fingerprint',
      isSuccess: (value) => value.ok,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(result.ok, isFalse);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a returned success result still shows a tick', (tester) async {
    await tester.pumpWidget(_host());

    await TransactionUiService.instance.run<({bool ok})>(
      () async => (ok: true),
      label: 'Verifying face',
      isSuccess: (value) => value.ok,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('shows a cross on failure and rethrows', (tester) async {
    await tester.pumpWidget(_host());

    final completer = Completer<int>();
    final future = TransactionUiService.instance.run(
      () => completer.future,
      label: 'Saving',
    );

    await tester.pump();
    completer.completeError(StateError('nope'));

    await expectLater(future, throwsStateError);
    await tester.pump();

    expect(find.byIcon(Icons.close), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('runDetached reports a false result without throwing',
      (tester) async {
    await tester.pumpWidget(_host());

    final ok = await TransactionUiService.instance.runDetached(
      () async => false,
      label: 'Checking out',
    );
    await tester.pump();

    expect(ok, isFalse);
    expect(find.byIcon(Icons.close), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.byIcon(Icons.close), findsNothing);
  });
}
