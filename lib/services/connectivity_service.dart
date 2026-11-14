import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

/// One reachability check. Returns `true` when the device can reach the backend.
///
/// Injected rather than hardcoded so the whole sampling loop can be driven from
/// tests: a fake probe means no sockets, no platform channels, and no waiting on
/// a real TCP handshake.
typedef ConnectivityProbe = Future<bool> Function();

/// What one connection attempt concluded.
enum _Reach {
  connected,

  /// The OS answered: no route to host, or the port refused the connection.
  /// Airplane mode, a pulled cable and a dead tower all land here.
  refused,

  /// No answer within the timeout. A congested radio looks exactly like a dead
  /// one, so this is not conclusive on its own.
  timedOut,
}

/// The verdict of one full probe across every configured host.
class _ProbeOutcome {
  const _ProbeOutcome({required this.reachable, required this.definitive});

  final bool reachable;

  /// True when nothing connected **and** every attempt was refused rather than
  /// timed out — the OS itself said there is no network.
  final bool definitive;
}

/// Samples whether the backend is reachable and publishes the answer.
///
/// The app already knows how to *fail* when the network is gone — it just does
/// it one screen and several seconds at a time, as a spinner that eventually
/// turns into an error a user has to dismiss. This service answers the same
/// question ahead of time and continuously, so the UI can block once and unblock
/// itself automatically.
///
/// Reachability is judged by opening a TCP connection to the API host, not by
/// asking the platform and not by pinging a generic internet host:
///
/// * A platform connectivity check reports "wifi connected" on a captive portal,
///   on a router with no upstream, and on office networks that blackhole the HRM
///   host specifically. The connection exists; the app still cannot work.
/// * A generic public host (`8.8.8.8`, `google.com`) answers fine while the
///   backend is down for maintenance, which would leave the app claiming to be
///   online in exactly the case the overlay exists to cover.
///
/// A TCP handshake to the same host and port the API calls use is the cheapest
/// signal that matches what the app actually needs: one packet instead of a full
/// HTTPS round trip, and the answer is about *our* server rather than about the
/// internet in general.
///
/// Two consecutive failures are required before the state flips to offline. A
/// single drop happens constantly on mobile data — a lift, a tunnel, a tower
/// handover — and throwing a full-screen overlay on one lost packet would make
/// the app feel broken. Recovery is deliberately asymmetric: the first
/// successful probe flips it back, because keeping a blocking overlay on screen
/// after the network is demonstrably back is the worse failure of the two.
class ConnectivityService {
  ConnectivityService({
    ConnectivityProbe? probe,
    Duration? checkInterval,
    Duration? offlineRetryInterval,
    Duration? confirmDelay,
  })  : _customProbe = probe,
        _checkInterval = checkInterval ?? const Duration(milliseconds: 1500),
        _offlineRetryInterval =
            offlineRetryInterval ?? const Duration(seconds: 1),
        _confirmDelay = confirmDelay ?? const Duration(milliseconds: 250);

  /// The app-wide sampler, used by `ConnectivityGuard` when nothing is injected.
  static final ConnectivityService instance = ConnectivityService();

  /// Failed probes needed before the state is published as offline.
  static const int _failuresBeforeOffline = 2;

  /// Ceiling on one TCP handshake.
  ///
  /// A handshake to a healthy host on mobile data completes in well under 300ms.
  /// This used to be 3s, which set the detection floor: a blackholed packet cost
  /// three full seconds *per sample*, and the tolerance below needs two samples.
  /// 800ms still clears any realistic handshake while capping that cost.
  static const Duration _connectTimeout = Duration(milliseconds: 800);

  /// Pause before the confirming sample when the first failure was a timeout
  /// rather than a definitive refusal.
  ///
  /// A refused or unroutable connect is the OS answering a question — airplane
  /// mode, a pulled cable, a dead tower — so the confirming sample starts
  /// immediately. A *timeout* is ambiguous (a congested radio looks identical to
  /// a dead one), so the second attempt waits a beat; without that, one slow
  /// handshake could produce two failures in a row with no chance of recovering
  /// between them.
  final Duration _confirmDelay;

  /// The injected probe, when a test supplies one.
  ///
  /// Tests only need "up" or "down", so the public contract stays a bool. The
  /// refusal/timeout distinction is used solely to decide how fast the
  /// confirming sample follows, and a fake link has no transport to classify.
  final ConnectivityProbe? _customProbe;

  /// How long to wait before the next scheduled sample while healthy.
  ///
  /// Halved from 3s. This interval, not the timeout, is most of the latency a
  /// user feels: a drop that happens just after a successful sample waits here
  /// first.
  final Duration _checkInterval;

  /// Faster while offline, so the overlay clears within a second of the network
  /// returning instead of leaving the user staring at it.
  final Duration _offlineRetryInterval;

  /// Starts `true`: at launch the app has not yet proved otherwise, and claiming
  /// offline before the first probe would flash the overlay over a working
  /// connection on every cold start.
  final ValueNotifier<bool> _isOnline = ValueNotifier<bool>(true);

  ValueNotifier<bool> get isOnline => _isOnline;

  Timer? _timer;

  /// One-shot second sample, fired the moment the first one fails.
  ///
  /// Waiting for the periodic tick was the largest single source of lag: a drop
  /// just after a good sample paid up to a full [_checkInterval] before the
  /// confirming sample even started, so the user saw the spinner/overlay arrive
  /// seconds after the network was gone. Confirming here instead cuts that wait
  /// to [_confirmDelay].
  Timer? _confirmTimer;

  /// The probe currently awaiting its handshake, if any.
  ///
  /// A request that arrives while one is open joins it instead of opening a
  /// second socket. Two handshakes started a few milliseconds apart describe the
  /// same instant of downtime, and counting both would satisfy the two-failure
  /// anti-flap rule on a single drop — the exact mistake the rule exists to
  /// prevent. It matters in practice because the timer cadence is shorter than
  /// [_connectTimeout]: a dead host would otherwise always have two probes in
  /// flight, and a resume (start, then probeNow) would arm two immediately.
  Future<void>? _inFlight;

  int _consecutiveFailures = 0;

  /// Bumped by [start] and [stop]. A probe captures it before awaiting and drops
  /// its result when it no longer matches, which is what stops a probe that was
  /// already in flight from changing the state after [stop] — the app is in the
  /// background at that point, and a stale "offline" would be painted over the
  /// first frame of the next resume.
  int _generation = 0;

  bool _disposed = false;

  bool get isRunning => _timer != null;

  /// Begins sampling. Idempotent, so a resume delivered twice cannot arm two
  /// timers.
  void start() {
    if (_disposed || _timer != null) return;

    // Resuming is a fresh look at the network: whatever the failure count was
    // when the app went to the background described a network that no longer
    // necessarily exists.
    _generation++;
    _consecutiveFailures = 0;
    // Any probe still open belongs to the generation just abandoned, so the one
    // below must not be merged into it — its result will be thrown away.
    _inFlight = null;
    _cancelConfirm();
    _armTimer(_isOnline.value ? _checkInterval : _offlineRetryInterval);

    // Probed now rather than after one interval, so a session that resumes with
    // the network already gone is covered immediately instead of 1.5 seconds in.
    unawaited(probeNow());
  }

  /// Pauses sampling. Safe to call when not running.
  ///
  /// The last known state is kept: callers stop this while the app is in the
  /// background, and a paused app that comes back to the same network should not
  /// have to re-prove it before the first frame is usable.
  void stop() {
    _timer?.cancel();
    _timer = null;

    // Invalidates any probe still waiting on a handshake so its result is
    // discarded rather than published after the app has been paused.
    _generation++;
    _consecutiveFailures = 0;
    _inFlight = null;
    _cancelConfirm();
  }

  /// Runs one probe right now, outside the timer cadence.
  ///
  /// Used on resume and on the first frame: the network can change while the app
  /// is in the background, and waiting for the next tick would show the wrong
  /// state for up to an interval. Awaits the probe that is already open rather
  /// than starting a competing one; either way the rule for callers is the same
  /// — when this completes, the answer has been applied or discarded.
  Future<void> probeNow() {
    if (_disposed) return Future<void>.value();

    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    final probe = _probeOnce();
    _inFlight = probe;

    return probe.whenComplete(() {
      if (identical(_inFlight, probe)) {
        _inFlight = null;
      }
    });
  }

  void dispose() {
    stop();
    _disposed = true;
    _isOnline.dispose();
  }

  Future<void> _probeOnce() async {
    final generation = _generation;

    _ProbeOutcome outcome;
    try {
      outcome = await _runProbe();
    } catch (error) {
      // A throwing prober is a failed probe, never a crash: this runs on a timer
      // for the entire life of the app. A thrown [SocketException] still carries
      // the transport's verdict, so a refusal keeps its fast path; anything else
      // says nothing about why and takes the cautious route.
      debugPrint('ConnectivityService: probe threw ($error)');
      outcome = _ProbeOutcome(
        reachable: false,
        definitive: error is SocketException && _isRefusal(error),
      );
    }

    // Stopped, restarted or disposed while this probe was in flight — discard.
    if (_disposed || generation != _generation) return;

    if (outcome.reachable) {
      // One success is enough to come back. A user who has just reconnected
      // should not be made to wait through a second sample to get their screen
      // back.
      _cancelConfirm();
      _consecutiveFailures = 0;
      _publish(true);
      return;
    }

    _consecutiveFailures++;
    if (_consecutiveFailures >= _failuresBeforeOffline) {
      _cancelConfirm();
      _publish(false);
      return;
    }

    // First failure: the tolerance says stay online, but do not sit on the
    // question until the next tick. Schedule the confirming sample immediately
    // so the second answer arrives in [_confirmDelay] rather than up to
    // [_checkInterval] later.
    _scheduleConfirm(definitive: outcome.definitive);
  }

  /// Arms the one-shot confirming sample after a first failure.
  ///
  /// [definitive] means the OS itself answered — no route, connection refused.
  /// There is nothing still in flight to give a second chance to, so the
  /// confirming sample starts at once and airplane mode is detected in one
  /// round trip instead of two. An ambiguous failure (a timeout, where a
  /// congested radio looks exactly like a dead one) waits [_confirmDelay] first.
  ///
  /// Only while the sampler is running. A manual [probeNow] against a stopped
  /// service (the guard never does this, but a test or a future caller might)
  /// must not leave a timer alive that wakes the process after [stop].
  void _scheduleConfirm({bool definitive = false}) {
    if (_disposed || _timer == null) return;

    // Replaced rather than stacked: two failure results landing together must
    // still produce only one confirming sample.
    _confirmTimer?.cancel();
    _confirmTimer = Timer(definitive ? Duration.zero : _confirmDelay, () {
      _confirmTimer = null;
      unawaited(probeNow());
    });
  }

  /// Runs one probe: the injected fake when there is one, otherwise a real
  /// handshake against every configured host.
  Future<_ProbeOutcome> _runProbe() async {
    final custom = _customProbe;
    if (custom != null) {
      // An injected link has no transport, so nothing can be called "definitive".
      // Tests that care about the fast path drive it through the real prober.
      return _ProbeOutcome(reachable: await custom(), definitive: false);
    }
    return _probeConfiguredHosts();
  }

  void _cancelConfirm() {
    _confirmTimer?.cancel();
    _confirmTimer = null;
  }

  void _publish(bool next) {
    // Nothing to tell the UI, and the timer keeps its current cadence.
    if (_isOnline.value == next) return;

    _isOnline.value = next;

    // Re-armed only when running: a manual [probeNow] against a stopped service
    // must not resurrect the timer.
    if (_timer == null) return;
    _armTimer(next ? _checkInterval : _offlineRetryInterval);
  }

  void _armTimer(Duration interval) {
    // Cancelled before a replacement is created so two timers can never be
    // alive at once after a state flip.
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) {
      // A confirming sample is already on its way. Probing here too would run two
      // handshakes describing the same instant, and the second one could advance
      // the failure count on a single real drop — the anti-flap rule would be
      // satisfied by one event.
      if (_confirmTimer != null) return;
      unawaited(probeNow());
    });
  }

  /// Opens a TCP connection to every configured API host and reports whether any
  /// of them answered, and — when none did — whether that was the OS refusing or
  /// merely silence.
  ///
  /// Every candidate is tried because the app itself fails over between them;
  /// reporting offline while a fallback host is reachable would block a session
  /// that could have worked. `eagerError: false` keeps the remaining candidates
  /// in the race after the first one fails — the primary host is exactly the one
  /// most likely to be unreachable on a tunnel-only development network.
  static Future<_ProbeOutcome> _probeConfiguredHosts() async {
    final bases = AppConfig.authApiBaseUrlCandidates.isNotEmpty
        ? AppConfig.authApiBaseUrlCandidates
        : AppConfig.attendanceApiBaseUrlCandidates;

    // Deduplicated: the candidate list is a primary URL plus configured
    // alternates, and two of them can point at the same socket. A dead host must
    // cost one timeout, not one per list entry.
    final targets = <(String, int)>{};
    for (final base in bases) {
      final uri = Uri.tryParse(base.trim());
      if (uri == null || uri.host.isEmpty) continue;
      targets.add((uri.host, _portFor(uri)));
    }

    if (targets.isEmpty) {
      debugPrint('ConnectivityService: no API host configured to probe');
      return const _ProbeOutcome(reachable: false, definitive: false);
    }

    final results = await Future.wait(
      targets.map((target) => _canConnect(target.$1, target.$2)),
      eagerError: false,
    );

    if (results.any((result) => result == _Reach.connected)) {
      return const _ProbeOutcome(reachable: true, definitive: false);
    }

    // Definitive only when *every* host refused outright. One silent host means
    // a firewall or a blackhole may be hiding a working network, and that
    // deserves the cautious confirmation delay rather than an instant verdict.
    final refusedEverywhere = results.every((result) => result == _Reach.refused);
    return _ProbeOutcome(reachable: false, definitive: refusedEverywhere);
  }

  /// An explicit `https`/`http` scheme decides the port, because a base URL is
  /// written without one and [Uri.port] would otherwise fall back to 0 for a
  /// schemeless value such as a bare `host:8000`.
  static int _portFor(Uri uri) {
    return switch (uri.scheme) {
      'https' => 443,
      'http' => 80,
      _ => uri.port,
    };
  }

  static Future<_Reach> _canConnect(String host, int port) async {
    try {
      final socket = await Socket.connect(host, port, timeout: _connectTimeout);
      // Destroyed rather than closed: nothing is written to this socket, so a
      // graceful close would only hold the probe open for as long as the peer
      // cares to keep the connection.
      socket.destroy();
      return _Reach.connected;
    } on SocketException catch (error) {
      debugPrint('ConnectivityService: $host:$port unreachable ($error)');
      return _isRefusal(error) ? _Reach.refused : _Reach.timedOut;
    } catch (error) {
      debugPrint('ConnectivityService: $host:$port failed ($error)');
      return _Reach.timedOut;
    }
  }

  /// Whether a failed connect was the OS saying "no", rather than silence.
  ///
  /// The errno set differs per platform, so both are listed: Android is Linux, so
  /// airplane mode surfaces as ENETUNREACH (101) or EHOSTUNREACH (113) and a
  /// closed port as ECONNREFUSED (111); the values in parentheses are the BSD /
  /// Windows equivalents (51 / 65 / 61) for a probe run on a desktop host.
  ///
  /// Anything else — including the timeout sentinel, which carries no OS error at
  /// all — stays ambiguous on purpose.
  static bool _isRefusal(SocketException error) {
    final code = error.osError?.errorCode;
    if (code == null) return false;
    return code == 101 || // ENETUNREACH
        code == 113 || // EHOSTUNREACH
        code == 111 || // ECONNREFUSED
        code == 51 || // ENETUNREACH (BSD/macOS)
        code == 65 || // EHOSTUNREACH (BSD/macOS)
        code == 61; // ECONNREFUSED (BSD/macOS)
  }
}
