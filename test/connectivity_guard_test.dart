import 'package:employee_attendance/services/connectivity_service.dart';
import 'package:employee_attendance/widgets/connectivity_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget coverage for the foreground connectivity guard.
///
/// The guard is what actually protects a field officer from working against a
/// dead link. Three risks drive the cases below:
///
///  * **False alarms.** If the overlay appeared on a single dropped probe, a
///    punch would be refused mid-gesture for no reason. The blur must wait for
///    the second consecutive failure.
///  * **Leaks while offline.** An overlay that only *looks* opaque still lets
///    taps, and the system back, reach the form underneath - so a user could
///    edit a record or lose a half-filled form believing nothing was happening.
///    The blocked-tap and blocked-back cases are deliberately discriminating:
///    the control is present and findable, it simply never fires.
///  * **Lost work.** When the link comes back the user must land exactly where
///    they were, with their typed text intact, not on a rebuilt screen.
///
/// The guard must also stop sampling when the app is not in the foreground: a
/// probe every few seconds from a backgrounded app keeps a radio awake and can
/// flip the UI offline for a screen the user cannot even see.
///
/// Nothing here touches a socket or a platform channel. The service is a real
/// [ConnectivityService] whose probe is an injected closure over a local bool,
/// and every interval is a few milliseconds that `tester.pump()` advances.
void main() {
  /// The exact headline the overlay must show.
  const String headline = "Can't connect to the internet";

  /// Injected cadence. Small enough that a handful of pumps stands in for a
  /// minute of sampling; there is no real waiting anywhere in this file.
  const Duration tick = Duration(milliseconds: 10);

  /// A probe backed by a mutable flag instead of the network.
  bool reachable = true;
  int probeCalls = 0;

  setUp(() {
    reachable = true;
    probeCalls = 0;
  });

  ConnectivityService buildService() {
    final service = ConnectivityService(
      probe: () {
        probeCalls += 1;
        return Future<bool>.value(reachable);
      },
      checkInterval: tick,
      offlineRetryInterval: tick,
    );
    // Backstop only: every test parks the sampler itself, because the leak
    // check rejects a pending timer before this would run.
    addTearDown(() {
      if (service.isRunning) service.stop();
    });
    return service;
  }

  /// Advances the fake clock in [tick] steps until the service has sampled at
  /// least [target] times. Pumping past an extra sample is harmless - the tests
  /// only ever assert on a state they have already committed to.
  Future<void> pumpUntilSamples(WidgetTester tester, int target) async {
    for (var i = 0; i < 200 && probeCalls < target; i++) {
      await tester.pump(tick);
    }
    expect(
      probeCalls,
      greaterThanOrEqualTo(target),
      reason: 'expected at least $target samples',
    );
  }

  /// Lets the overlay's transition finish. Only needed so the assertions look
  /// at a settled tree; nothing depends on the animation itself.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Takes the connection down and waits until the guard has acted on it.
  Future<void> goOffline(WidgetTester tester) async {
    reachable = false;
    await pumpUntilSamples(tester, probeCalls + 2);
    await settle(tester);
  }

  /// Brings the connection back and waits until the guard has acted on it.
  Future<void> goOnline(WidgetTester tester) async {
    reachable = true;
    await pumpUntilSamples(tester, probeCalls + 1);
    await settle(tester);
  }

  Future<ConnectivityService> pumpGuard(
    WidgetTester tester,
    Widget child,
  ) async {
    // flutter_test starts with no lifecycle state; saying "resumed" out loud is
    // what tells the guard the app is in the foreground.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final service = buildService();
    await tester.pumpWidget(
      MaterialApp(home: ConnectivityGuard(service: service, child: child)),
    );
    await tester.pump();
    return service;
  }

  group('ConnectivityGuard - foreground sampling', () {
    testWidgets('samples while the app is in the foreground', (tester) async {
      final service = await pumpGuard(tester, const SizedBox.expand());

      expect(service.isRunning, isTrue);
      await pumpUntilSamples(tester, 1);

      service.stop();
    });

    testWidgets('leaving the foreground cancels sampling', (tester) async {
      addTearDown(() => tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      final service = await pumpGuard(tester, const SizedBox.expand());
      await pumpUntilSamples(tester, 1);
      final parked = probeCalls;

      // `inactive` is what a notification shade or app switcher produces, and
      // `paused` is a backgrounded app. Neither may keep probing.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(service.isRunning, isFalse);
      await tester.pump(const Duration(milliseconds: 200));
      expect(probeCalls, parked);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(service.isRunning, isFalse);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        probeCalls,
        parked,
        reason: 'no sampling while the user is in another app',
      );

      service.stop();
    });

    testWidgets('returning to the foreground resumes sampling', (tester) async {
      addTearDown(() => tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      final service = await pumpGuard(tester, const SizedBox.expand());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final parked = probeCalls;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(service.isRunning, isTrue);
      await pumpUntilSamples(tester, parked + 1);

      service.stop();
    });
  });

  group('ConnectivityGuard - offline overlay', () {
    testWidgets('the headline waits for the second failure', (tester) async {
      final service = await pumpGuard(
        tester,
        const Scaffold(body: Center(child: _TapCounter())),
      );
      expect(find.text(headline), findsNothing);

      reachable = false;
      await pumpUntilSamples(tester, probeCalls + 1);
      await tester.pump();
      expect(
        find.text(headline),
        findsNothing,
        reason: 'one dropped packet must not blur the screen',
      );

      await goOffline(tester);
      expect(find.text(headline), findsOneWidget);

      service.stop();
    });

    testWidgets('the headline clears on the first successful sample',
        (tester) async {
      final service = await pumpGuard(
        tester,
        const Scaffold(body: Center(child: _TapCounter())),
      );
      await goOffline(tester);
      expect(find.text(headline), findsOneWidget);

      await goOnline(tester);
      expect(find.text(headline), findsNothing);

      service.stop();
    });
  });

  group('ConnectivityGuard - blocking', () {
    testWidgets('taps underneath are blocked, then work again online',
        (tester) async {
      final service = await pumpGuard(
        tester,
        const Scaffold(body: Center(child: _TapCounter())),
      );
      expect(find.text('taps: 0'), findsOneWidget);

      await goOffline(tester);
      expect(find.text(headline), findsOneWidget);
      // The control is still on screen and still findable - it is the overlay
      // above it, not a rebuild, that must swallow the gesture.
      expect(find.text('Record attendance'), findsOneWidget);

      await tester.tap(find.text('Record attendance'), warnIfMissed: false);
      await tester.pump();
      expect(
        find.text('taps: 0'),
        findsOneWidget,
        reason: 'the overlay must swallow the tap',
      );

      await tester.tap(find.text('Record attendance'), warnIfMissed: false);
      await tester.pump();
      expect(
        find.text('taps: 0'),
        findsOneWidget,
        reason: 'every tap is swallowed, not just the first',
      );

      await goOnline(tester);
      expect(find.text(headline), findsNothing);
      await tester.tap(find.text('Record attendance'));
      await tester.pump();
      expect(
        find.text('taps: 1'),
        findsOneWidget,
        reason: 'the same control must work once connectivity is back',
      );

      service.stop();
    });

    testWidgets('a system back does not leave the screen while offline',
        (tester) async {
      final service = buildService();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ConnectivityGuard(
                        service: service,
                        child: const Scaffold(body: Text('protected form')),
                      ),
                    ),
                  ),
                  child: const Text('Open form'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();
      expect(find.text('protected form'), findsOneWidget);

      await goOffline(tester);
      expect(find.text(headline), findsOneWidget);

      // Exactly what Android's back button and iOS's back swipe deliver.
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(
        find.text('protected form'),
        findsOneWidget,
        reason: 'the system back must be blocked while offline',
      );

      await goOnline(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.text('protected form'),
        findsNothing,
        reason: 'back must work again once connectivity returns',
      );

      service.stop();
    });
  });

  group('ConnectivityGuard - child state', () {
    testWidgets('a half-typed field keeps its text across the round trip',
        (tester) async {
      final service = await pumpGuard(
        tester,
        const Scaffold(
          body: Center(
            child: TextField(decoration: InputDecoration(labelText: 'Note')),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'site 42');
      await tester.pump();
      expect(find.text('site 42'), findsOneWidget);

      await goOffline(tester);
      expect(find.text(headline), findsOneWidget);
      // Still there underneath the overlay: the user can see what they must not
      // lose while they wait for the link.
      expect(find.text('site 42'), findsOneWidget);

      await goOnline(tester);
      expect(
        find.text('site 42'),
        findsOneWidget,
        reason: 'the overlay must not rebuild the child from scratch',
      );

      service.stop();
    });
  });
}

/// A counter button used to prove that gestures do or do not get through.
///
/// It keeps its own [State], so it doubles as the "control that must not be
/// rebuilt" in the blocked-tap case: a rebuild would reset the count and make a
/// blocked tap indistinguishable from a successful one.
class _TapCounter extends StatefulWidget {
  const _TapCounter();

  @override
  State<_TapCounter> createState() => _TapCounterState();
}

class _TapCounterState extends State<_TapCounter> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('taps: $_taps'),
        TextButton(
          onPressed: () => setState(() => _taps += 1),
          child: const Text('Record attendance'),
        ),
      ],
    );
  }
}
