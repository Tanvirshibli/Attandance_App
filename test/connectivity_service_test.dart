import 'dart:async';
import 'dart:io' show OSError, SocketException;

import 'package:employee_attendance/services/connectivity_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit coverage for the connectivity sampler that gates the app's UI.
///
/// The sampler decides when the app declares itself offline, and that decision
/// is expensive to get wrong in both directions:
///
///  * One failed probe is normal on a Bangladeshi mobile network - a lift, a
///    tin roof, a hand-off between towers. Blurring the whole screen on a
///    single dropped packet means a field officer's attendance punch can be
///    refused mid-gesture for no reason at all. So the service tolerates one
///    consecutive failure and only reports offline on the second.
///  * Recovering quickly matters just as much: the first successful probe must
///    bring the UI straight back, not wait for a streak of good samples.
///  * The sampler must be genuinely stoppable. If `stop()` left a probe in
///    flight, its late result could flip the app offline while it is
///    backgrounded (or, worse, flip a torn-down app back online), and a timer
///    that outlives its owner keeps the device awake for nothing.
///
/// Every probe here is injected. Nothing in this file opens a socket, calls a
/// platform channel or looks at the wall clock: the "connection" is a mutable
/// bool and the clock is either an hour-long interval that never fires (for the
/// state-machine tests) or the fake clock `tester.pump()` drives (for cadence).
void main() {
  /// Long enough that the periodic sampler cannot fire during a plain `test`,
  /// so those cases are driven purely by [ConnectivityService.probeNow] and
  /// never wait for time to pass.
  const Duration idleInterval = Duration(hours: 1);

  /// The cadence group's short interval: a few `tester.pump`s stand in for a
  /// whole minute of real sampling.
  const Duration tickInterval = Duration(milliseconds: 10);

  late _FakeProbe probe;

  setUp(() => probe = _FakeProbe());

  /// Builds a service on the fake probe and guarantees its timer is cancelled
  /// even when an expectation fails halfway through a test.
  ConnectivityService buildService({
    Duration interval = idleInterval,
    Duration? confirmDelay,
  }) {
    final service = ConnectivityService(
      probe: probe.call,
      checkInterval: interval,
      offlineRetryInterval: interval,
      confirmDelay: confirmDelay,
    );
    addTearDown(() {
      // Safe after dispose() too: `isRunning` is only a flag.
      if (service.isRunning) service.stop();
    });
    return service;
  }

  /// Starts the sampler and settles the probe it fires immediately.
  ///
  /// `start()` probes eagerly, so a resume onto a network that is already gone
  /// is covered without waiting a whole interval. That probe is therefore in
  /// flight by the time `start()` returns, and `probeNow()` joins an open probe
  /// instead of starting a competing one — so a test that flips the link right
  /// after `start()` would otherwise be describing a probe that already read the
  /// old value, and its first "failure" would never be counted. Draining the
  /// eager probe first is what makes the samples that follow mean anything.
  Future<ConnectivityService> startedService({
    Duration interval = idleInterval,
  }) async {
    final service = buildService(interval: interval);
    service.start();
    await service.probeNow();
    return service;
  }

  group('ConnectivityService - failure tolerance', () {
    test('starts online and idle', () {
      final service = buildService();

      // The app must be usable on the very first frame: the first sample has
      // not landed yet, so anything but "online" would show the offline screen
      // to every user at every cold start.
      expect(service.isOnline.value, isTrue);
      expect(service.isRunning, isFalse);
    });

    test('one failed probe keeps the app online', () async {
      final service = await startedService();
      probe.reachable = false;

      await service.probeNow();

      expect(
        service.isOnline.value,
        isTrue,
        reason: 'a single dropped packet must not blur the screen mid-punch',
      );
    });

    test('the second consecutive failure flips the app offline', () async {
      final service = await startedService();
      probe.reachable = false;

      await service.probeNow();
      expect(service.isOnline.value, isTrue);

      await service.probeNow();
      expect(service.isOnline.value, isFalse);
    });

    test('a successful probe in between resets the failure streak', () async {
      final service = await startedService();

      probe.reachable = false;
      await service.probeNow();
      probe.reachable = true;
      await service.probeNow();
      probe.reachable = false;
      await service.probeNow();

      // Two failures are on record, but never two *consecutive* ones, so the
      // count must have been reset by the success in the middle.
      expect(service.isOnline.value, isTrue);
    });

    test('the first successful probe while offline restores online', () async {
      final service = await startedService();
      probe.reachable = false;
      await service.probeNow();
      await service.probeNow();
      expect(service.isOnline.value, isFalse);

      probe.reachable = true;
      await service.probeNow();

      expect(
        service.isOnline.value,
        isTrue,
        reason: 'recovery must not wait for a second good sample',
      );
    });

    test('isOnline is one stable notifier that fires on the transition', () async {
      final service = await startedService();
      final seen = <bool>[];
      void listener() => seen.add(service.isOnline.value);
      service.isOnline.addListener(listener);
      addTearDown(() => service.isOnline.removeListener(listener));

      probe.reachable = false;
      await service.probeNow();
      await service.probeNow();

      // A listener attached before the flip has to see it: the guard rebuilds
      // by listening, so a notifier that is recreated per read would leave the
      // overlay stuck on the previous state.
      expect(seen, <bool>[false]);
    });
  });

  group('ConnectivityService - stop, start and dispose', () {
    test('stop marks the sampler stopped', () {
      final service = buildService()..start();
      expect(service.isRunning, isTrue);

      service.stop();

      expect(service.isRunning, isFalse);
    });

    test('a probe result that lands after stop is ignored', () async {
      final service = await startedService();
      probe.reachable = false;
      await service.probeNow();
      await service.probeNow();
      expect(service.isOnline.value, isFalse);

      // Hold the next probe open and stop the service while it is in flight.
      probe.gate = Completer<bool>();
      unawaited(service.probeNow());
      await Future<void>.delayed(Duration.zero);
      expect(
        probe.gateTaken,
        isTrue,
        reason: 'the probe must actually be in flight for this case to mean '
            'anything',
      );

      service.stop();
      expect(service.isRunning, isFalse);

      // A late success, if it were applied, would flip the app back online.
      probe.gate!.complete(true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        service.isOnline.value,
        isFalse,
        reason: 'stop() froze the state; a late result must not thaw it',
      );
    });

    test('stop is safe to call twice', () {
      final service = buildService()..start();

      service.stop();
      service.stop();

      expect(service.isRunning, isFalse);
    });

    test('dispose stops the sampler', () {
      final service = buildService()..start();

      service.dispose();

      expect(service.isRunning, isFalse);
    });

    test('instance is a shared singleton', () {
      // ConnectivityGuard falls back to this instance when no service is
      // injected, so it has to be one object rather than a fresh one per read.
      expect(ConnectivityService.instance, same(ConnectivityService.instance));
    });
  });

  /// Driven by `tester.pump()`: `testWidgets` already runs its body inside a
  /// fake clock, which gives the cadence assertions exact control over time
  /// without adding `fake_async` as a dependency or waiting on a real timer.
  group('ConnectivityService - sampler cadence', () {
    Future<void> pumpUntilSamples(WidgetTester tester, int target) async {
      for (var i = 0; i < 200 && probe.calls < target; i++) {
        await tester.pump(tickInterval);
      }
      expect(
        probe.calls,
        greaterThanOrEqualTo(target),
        reason: 'expected at least $target samples',
      );
    }

    testWidgets('a started service samples on the injected interval',
        (tester) async {
      final service = buildService(interval: tickInterval);

      await tester.pump(tickInterval);
      expect(probe.calls, 0, reason: 'nothing is sampled before start()');

      service.start();
      await pumpUntilSamples(tester, 1);
      await pumpUntilSamples(tester, 3);

      service.stop();
    });

    testWidgets('sampling, not just probeNow, applies the tolerance',
        (tester) async {
      final service = buildService(interval: tickInterval)..start();
      await pumpUntilSamples(tester, 1);

      probe.reachable = false;
      await pumpUntilSamples(tester, 2);
      expect(service.isOnline.value, isTrue);

      await pumpUntilSamples(tester, 3);
      expect(service.isOnline.value, isFalse);

      probe.reachable = true;
      await pumpUntilSamples(tester, 4);
      expect(service.isOnline.value, isTrue);

      service.stop();
    });

    testWidgets('stop cancels the pending sample', (tester) async {
      final service = buildService(interval: tickInterval)..start();
      await pumpUntilSamples(tester, 1);
      final parked = probe.calls;

      service.stop();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        probe.calls,
        parked,
        reason: 'a cancelled sampler must not keep probing in the background',
      );
    });

    testWidgets('start after stop samples again', (tester) async {
      final service = buildService(interval: tickInterval)..start();
      await pumpUntilSamples(tester, 1);
      service.stop();
      await tester.pump(const Duration(milliseconds: 200));
      final parked = probe.calls;

      service.start();

      expect(service.isRunning, isTrue);
      await pumpUntilSamples(tester, parked + 1);

      service.stop();
    });

    testWidgets('dispose stops the sampler for good', (tester) async {
      final service = buildService(interval: tickInterval)..start();
      await pumpUntilSamples(tester, 1);
      final parked = probe.calls;

      service.dispose();
      await tester.pump(const Duration(milliseconds: 200));

      expect(probe.calls, parked);
    });
  });

  /// The detection latency.
  ///
  /// The user-visible promise is "the app notices the drop within a second or
  /// two", and that promise is made of two numbers a reader cannot check by
  /// looking at the code: how soon the next sample starts, and how fast the
  /// confirming sample follows. These cases pin both, so a future change that
  /// quietly restores "wait for the next tick" fails here instead of in the
  /// field. Everything runs on the test fake clock — no real waiting.
  group('ConnectivityService - detection latency', () {
    const Duration confirmDelay = Duration(milliseconds: 40);

    /// The number of samples at the moment the first failure is recorded.
    Future<int> settleStart(WidgetTester tester, ConnectivityService service) async {
      // The eager start() probe needs one turn to land before the baseline.
      await tester.pump();
      return probe.calls;
    }

    testWidgets('the confirming sample does not wait for the poll interval',
        (tester) async {
      // Hour-long interval: if the confirm probe only ever came from the tick,
      // this test would hang at the first assertion rather than pass.
      final service = buildService(confirmDelay: confirmDelay)..start();
      final baseline = await settleStart(tester, service);

      probe.reachable = false;
      await service.probeNow();
      expect(probe.calls, baseline + 1, reason: 'the failing sample');
      expect(
        service.isOnline.value,
        isTrue,
        reason: 'the tolerance still holds after one failure',
      );

      await tester.pump(confirmDelay);
      await tester.pump();

      expect(
        probe.calls,
        greaterThanOrEqualTo(baseline + 2),
        reason: 'the second sample must follow the first, not the 1-hour tick',
      );
      expect(service.isOnline.value, isFalse);

      service.stop();
    });

    testWidgets('an OS refusal confirms immediately', (tester) async {
      final service = buildService(confirmDelay: confirmDelay)..start();
      await settleStart(tester, service);

      // ENETUNREACH: what airplane mode actually reports on Android.
      probe.error = const SocketException(
        'No route to host',
        osError: OSError('Network is unreachable', 101),
      );
      await service.probeNow();
      expect(service.isOnline.value, isTrue);

      // No delay at all is configured for a refusal, so even a zero pump fires it.
      await tester.pump(Duration.zero);
      await tester.pump();

      expect(
        service.isOnline.value,
        isFalse,
        reason: 'a refusal is the OS answering; one round trip is enough',
      );

      service.stop();
    });

    testWidgets('an ambiguous timeout waits before confirming', (tester) async {
      final service = buildService(confirmDelay: confirmDelay)..start();
      final baseline = await settleStart(tester, service);

      // A generic failure carries no transport verdict: treat it as silence, not
      // as a refusal, so the link gets a beat to come back before we blur.
      probe.error = TimeoutException('no answer');
      await service.probeNow();
      expect(probe.calls, baseline + 1);

      await tester.pump(confirmDelay ~/ 2);
      expect(
        probe.calls,
        baseline + 1,
        reason: 'a congested radio must not be confirmed instantly',
      );

      await tester.pump(confirmDelay);
      await tester.pump();

      expect(probe.calls, greaterThanOrEqualTo(baseline + 2));
      expect(service.isOnline.value, isFalse);

      service.stop();
    });

    testWidgets('the poll tick does not double-count while a confirm is pending',
        (tester) async {
      const Duration tick = Duration(milliseconds: 30);
      final service = buildService(
        interval: tick,
        confirmDelay: const Duration(milliseconds: 90),
      )..start();
      final baseline = await settleStart(tester, service);

      probe.reachable = false;
      await service.probeNow();

      // Two ticks pass before the confirm is due. Neither may start a sample, or
      // one real drop would satisfy the two-failure rule by itself.
      await tester.pump(const Duration(milliseconds: 65));

      expect(
        probe.calls,
        baseline + 1,
        reason: 'one drop must not be counted twice by tick plus confirm',
      );
      expect(service.isOnline.value, isTrue);

      service.stop();
    });
  });
}

/// A probe backed by a mutable flag instead of a network call.
///
/// Real sockets in a widget test are both slow and uncontrollable - there is no
/// way to make a live link fail on exactly the second attempt - so the "line"
/// here is [reachable], and [gate] lets a single probe be held open to test a
/// result that arrives too late.
class _FakeProbe {
  /// Whether a probe that is not gated reports success.
  bool reachable = true;

  /// How many times the service has asked for the link state.
  int calls = 0;

  /// When set, the next probe hangs on this future instead of answering.
  Completer<bool>? gate;

  /// When set, probes throw this instead of answering.
  ///
  /// The service classifies a thrown [SocketException] by its errno, so a fake
  /// refusal is a real `SocketException` carrying a real errno rather than a
  /// bespoke test type — that keeps the classification under test.
  Object? error;

  /// Whether a probe has already parked on [gate].
  bool gateTaken = false;

  Future<bool> call() {
    calls += 1;
    final pending = gate;
    if (pending != null) {
      gateTaken = true;
      return pending.future;
    }
    final failure = error;
    if (failure != null) return Future<bool>.error(failure);
    return Future<bool>.value(reachable);
  }
}
