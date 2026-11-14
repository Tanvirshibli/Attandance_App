import 'dart:async';

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
  ConnectivityService buildService({Duration interval = idleInterval}) {
    final service = ConnectivityService(
      probe: probe.call,
      checkInterval: interval,
      offlineRetryInterval: interval,
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

  /// Whether a probe has already parked on [gate].
  bool gateTaken = false;

  Future<bool> call() {
    calls += 1;
    final pending = gate;
    if (pending != null) {
      gateTaken = true;
      return pending.future;
    }
    return Future<bool>.value(reachable);
  }
}
