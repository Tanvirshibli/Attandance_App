import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// One clock reading taken from one independent source.
///
/// [instant] is the source's clock at the midpoint of the exchange, in UTC.
/// [offsetMs] is that instant minus the device clock at the same midpoint, which
/// is what [InternetTimeService.deviceDriftSeconds] is built from.
/// [elapsedMicros] is the monotonic reading when the reply arrived, used to
/// project every sample onto one common moment before taking the median.
class _TimeSample {
  const _TimeSample({
    required this.instant,
    required this.offsetMs,
    required this.roundTripMs,
    required this.elapsedMicros,
    required this.source,
    required this.isNtp,
  });

  final DateTime instant;
  final int offsetMs;
  final int roundTripMs;
  final int elapsedMicros;
  final String source;
  final bool isNtp;
}

/// The outcome of one [InternetTimeService.sync] call.
///
/// [ok] is the only field a caller has to check. Every field is filled from that
/// sync, never from the persisted cache, so a failed refresh cannot make a
/// previous process's answer look fresh.
class InternetTimeSyncResult {
  const InternetTimeSyncResult({
    required this.ok,
    this.error,
    this.internetTime,
    this.sourceCount = 0,
    this.sourceLabel = 'no sources',
    this.accuracyMs = 0,
    this.deviceDriftSeconds = 0,
  });

  final bool ok;

  /// Plain-English reason the sync failed. Null when [ok].
  final String? error;

  /// Internet time at the moment the sync completed (UTC). Null when not [ok].
  final DateTime? internetTime;

  /// How many independent sources agreed. Two or more is a real quorum.
  final int sourceCount;

  /// Human label, e.g. `3 HTTPS sources` or `2 HTTPS sources + 1 NTP`.
  final String sourceLabel;

  /// Half-width of the uncertainty of [internetTime], in milliseconds.
  final int accuracyMs;

  /// `internet - device clock` at this sync, in seconds. Positive means the
  /// phone is behind; negative means it is ahead.
  final int deviceDriftSeconds;
}

/// Internet time, and the only clock the attendance flow is allowed to trust.
///
/// Why this exists
/// ---------------
/// A punch stamped with `DateTime.now()` is worth exactly what the device clock
/// is worth, and the device clock is a setting the user can edit. A phone set to
/// 09:58 while it is actually 18:00 punches in "on time" from the sofa. So the
/// app needs a clock it did not get from the phone, and it needs that clock to
/// keep working when the phone's clock is changed underneath it.
///
/// How the anchor works
/// --------------------
/// Two halves:
///
/// 1. **Find internet time.** Three independent HTTPS endpoints are asked for
///    their `Date` header. Each exchange is timed with a [Stopwatch], so a
///    reply's timestamp can be moved forward by half the round trip and treated
///    as the instant the reply describes. Three sources, median answer: one
///    slow or lying source cannot move the result, and the spread across them
///    is a usable accuracy figure. If fewer than two HTTPS sources answer,
///    plain SNTP over UDP 123 is tried as a fallback, so a network that strips
///    or mangles `Date` headers still works.
///
/// 2. **Freeze it against a monotonic source.** The result is stored as
///    `_anchorInternet` (UTC) plus `_anchorElapsedMicros` (a process-wide
///    [Stopwatch]). [now] is always `anchor + (elapsedNow - anchorElapsed)`. A
///    stopwatch counts real elapsed time and cannot be changed by the user, so
///    after the first sync the device clock can be moved, frozen or set to 1970
///    and [now] does not follow it. The measured offset is used *only* to derive
///    the anchor and to report [deviceDriftSeconds] — it is never re-applied
///    later.
///
/// What this deliberately does not do
/// ----------------------------------
/// * **No silent fallback to the device clock.** If nothing has ever synced,
///   [now] throws instead of quietly returning `DateTime.now()`. A caller that
///   cannot show a trustworthy time must say so, not guess; callers check
///   [isSynced] first.
/// * **Nothing is inferred from the persisted cache.** The last offset and sync
///   epoch are stored so a cold start can *display* what the previous session
///   found ([cachedSyncAt], [cachedDriftSeconds]), but [isSynced] stays false
///   until this process completes a live sync. A cached offset applied to a
///   clock that has since been moved forward would produce a confident, wrong,
///   "verified" timestamp — the worst possible outcome.
///
/// Failure behaviour
/// -----------------
/// [sync] never throws and never leaves the caller hanging: every network path
/// is timed out, every source failure is folded into the result, and a failure
/// says `ok: false` with a sentence a human can act on. Airplane mode is just
/// the empty-samples case.
class InternetTimeService {
  InternetTimeService._() {
    // Read the persisted "last verified" values straight away, so a cold start
    // that is offline can still show when the clock was last checked instead of
    // nothing at all. They never make `isSynced` true — see [_loadCacheOnce].
    unawaited(_loadCacheOnce());
  }

  /// The app-wide instance. Callers use this; there is no public constructor.
  static final InternetTimeService instance = InternetTimeService._();

  /// Resync cadence while the app is alive. A phone's clock can be changed at
  /// any moment, so "verified at launch" is not a property that survives an
  /// eight-hour shift.
  static const Duration autoResyncInterval = Duration(minutes: 15);

  /// A sync younger than this is trusted by [isHealthy] and by the drift check
  /// in `DeviceIntegrityService`.
  static const Duration healthyWindow = Duration(seconds: 300);

  /// Syncs closer together than this are collapsed into the answer already in
  /// hand, so a resume plus a check-in screen build plus a timer tick do not
  /// triple the traffic.
  static const Duration _minimumSyncGap = Duration(seconds: 45);

  static const Duration _httpsTimeout = Duration(seconds: 6);
  static const Duration _ntpTimeout = Duration(seconds: 4);

  /// Independent HTTPS sources: three different operators on three different
  /// edge networks, all of which set an accurate `Date` header and answer a
  /// HEAD cheaply. A captive portal or one bad proxy cannot take out all three.
  static const List<String> _httpsSources = <String>[
    'https://www.google.com',
    'https://www.cloudflare.com',
    'https://www.microsoft.com',
  ];

  /// SNTP fallback. UDP 123 needs no TLS, no proxy cooperation and no header
  /// rewriting, which is why it survives networks where `Date` does not.
  static const List<String> _ntpHosts = <String>[
    'time.google.com',
    'pool.ntp.org',
  ];

  static const int _ntpPort = 123;

  /// A sample further from the device clock than this is nonsense — a captive
  /// portal page, a broken proxy rewriting headers, or an NTP era overflow.
  /// Rejecting it keeps one bad source out of the median.
  static const Duration _sanityWindow = Duration(days: 365);

  static const String _offsetKey = 'integrity_time_offset_ms';
  static const String _syncEpochKey = 'integrity_time_sync_epoch_ms';

  /// Process-wide monotonic clock. Started once, never reset; every anchor is
  /// expressed as a reading of this stopwatch.
  static final Stopwatch _monotonic = Stopwatch()..start();

  /// Placeholder until the first live sync. A caller that binds to this without
  /// checking [isSynced] sees 1970, which is unmistakably wrong rather than
  /// plausibly wrong.
  final ValueNotifier<DateTime> _ticker = ValueNotifier<DateTime>(
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );

  final FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Internet time at the anchor, in UTC.
  DateTime? _anchorInternet;

  /// [_monotonic] reading at the moment the anchor was taken.
  int _anchorElapsedMicros = 0;

  /// Device wall-clock reading of the last sync. Informational only: used to
  /// say "synced at 09:12", never to compute time.
  DateTime? _lastSyncAt;

  /// [_monotonic] reading at the last sync, so the *age* of a sync cannot be
  /// falsified by moving the device clock.
  int _syncElapsedMicros = 0;

  int _deviceDriftSeconds = 0;
  int _accuracyMs = 0;
  int _sourceCount = 0;
  int _httpsCount = 0;
  int _ntpCount = 0;
  List<String> _contributingSources = const <String>[];

  InternetTimeSyncResult? _lastResult;

  /// The last *successful* result. [syncIfStale] hands this back when the anchor
  /// is fresh, so a caller never receives a failed refresh for a clock that is
  /// demonstrably fine.
  InternetTimeSyncResult? _lastSuccess;

  /// One sync at a time: the in-flight future is handed to every caller that
  /// arrives while it runs.
  Future<InternetTimeSyncResult>? _inFlight;

  Timer? _tickerTimer;
  Timer? _resyncTimer;

  bool _cacheLoaded = false;
  DateTime? _cachedSyncAt;
  int? _cachedDriftSeconds;

  /// True once *this process* has completed a live sync. Persistence never sets
  /// it.
  bool get isSynced => _anchorInternet != null;

  /// Synced recently enough to trust for a punch.
  bool get isHealthy =>
      isSynced &&
      syncAgeSeconds >= 0 &&
      syncAgeSeconds <= healthyWindow.inSeconds;

  /// Seconds since the last successful sync in this process, or `-1` when this
  /// process has never synced.
  ///
  /// The larger of two measurements, on purpose:
  ///
  /// * Elapsed **monotonic** time. Cannot be falsified by the user, which is why
  ///   it is the primary reading.
  /// * Elapsed **device wall-clock** time. Needed because Android's monotonic
  ///   clock stops counting while the device is asleep while the RTC does not, so
  ///   after a long sleep the monotonic reading *under*-reports the age of the
  ///   anchor — and an under-reported age would let a stale anchor look fresh
  ///   and skip the resync that fixes it.
  ///
  /// Taking the maximum can only ever make an anchor look older than it is,
  /// which forces a resync; over-reporting is harmless because a resync re-reads
  /// internet time and trusts the device clock no more than before.
  int get syncAgeSeconds {
    if (!isSynced) return -1;

    final monotonicAge =
        (_monotonic.elapsedMicroseconds - _syncElapsedMicros) ~/
            Duration.microsecondsPerSecond;

    final lastSync = _lastSyncAt;
    // A clock moved backwards gives a negative wall-clock age, which simply
    // loses the comparison.
    final wallClockAge =
        lastSync == null ? 0 : DateTime.now().difference(lastSync).inSeconds;

    return wallClockAge > monotonicAge ? wallClockAge : monotonicAge;
  }

  /// `internet - device clock` at the last sync, in seconds.
  ///
  /// Positive: the phone is slow (behind internet time). Negative: the phone is
  /// fast (ahead). Zero until the first sync.
  int get deviceDriftSeconds => isSynced ? _deviceDriftSeconds : 0;

  /// Half-width of the uncertainty of the last sync, in milliseconds: the spread
  /// between the sources plus half of the slowest round trip.
  int get accuracyMs => isSynced ? _accuracyMs : 0;

  /// e.g. `3 HTTPS sources` or `2 HTTPS sources + 1 NTP`.
  String get sourceLabel {
    if (_sourceCount == 0) return 'no sources';
    if (_ntpCount == 0) {
      return '$_httpsCount HTTPS source${_httpsCount == 1 ? '' : 's'}';
    }
    if (_httpsCount == 0) {
      return '$_ntpCount NTP source${_ntpCount == 1 ? '' : 's'}';
    }
    return '$_httpsCount HTTPS source${_httpsCount == 1 ? '' : 's'}'
        ' + $_ntpCount NTP';
  }

  /// How many sources contributed to the last sync.
  int get sourceCount => _sourceCount;

  /// Device wall-clock time of the last sync in this process (informational).
  DateTime? get lastSyncAt => _lastSyncAt;

  /// Emits every second while synced — and immediately after a sync, so a
  /// displayed clock jumps to the corrected value without waiting a tick.
  ///
  /// The value is internet time in **UTC**. Check [isSynced] before reading it:
  /// before the first sync it holds 1970-01-01, which is a sentinel, not a
  /// clock.
  ValueNotifier<DateTime> get ticker => _ticker;

  /// Sync epoch found in secure storage from a previous process, if any. For
  /// display on a cold start only; never used to compute time.
  DateTime? get cachedSyncAt => _cachedSyncAt;

  /// Drift recorded by a previous process, in seconds. Informational only.
  int? get cachedDriftSeconds => _cachedDriftSeconds;

  /// Internet time now, in **UTC** (call `.toLocal()` for display).
  ///
  /// Throws [StateError] when this process has never synced — a caller that
  /// needs a timestamp must check [isSynced] and refuse the action with a real
  /// message rather than stamping it with an unverified device clock.
  DateTime now() {
    final anchor = _anchorInternet;
    if (anchor == null) {
      throw StateError(
        'InternetTimeService.now() was called before the first successful '
        'sync. Check isSynced (or call sync()) first.',
      );
    }
    final elapsedMicros = _monotonic.elapsedMicroseconds - _anchorElapsedMicros;
    return anchor.add(Duration(microseconds: elapsedMicros));
  }

  /// Internet time now, or null before the first sync.
  ///
  /// For display and optimistic rows only. Anything that decides whether a
  /// punch is allowed must use [isSynced] + [now] so it fails closed.
  DateTime? get nowOrNull => _anchorInternet == null ? null : now();

  /// Fetches internet time and re-anchors. Never throws.
  ///
  /// [force] bypasses the [_minimumSyncGap] throttle but still joins a sync that
  /// is already running.
  Future<InternetTimeSyncResult> sync({bool force = false}) {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    final last = _lastResult;
    if (!force &&
        last != null &&
        last.ok &&
        isSynced &&
        syncAgeSeconds >= 0 &&
        syncAgeSeconds < _minimumSyncGap.inSeconds) {
      return Future<InternetTimeSyncResult>.value(last);
    }

    final run = _runSyncSafely();
    _inFlight = run;
    return run.whenComplete(() {
      if (identical(_inFlight, run)) _inFlight = null;
    });
  }

  /// Syncs only when the current anchor is older than [maxAge].
  ///
  /// For app-resume and screen-open hooks, which are frequent and must not each
  /// cost a round of requests.
  Future<InternetTimeSyncResult> syncIfStale({
    Duration maxAge = autoResyncInterval,
  }) {
    final success = _lastSuccess;
    if (success != null && isSynced && syncAgeSeconds >= 0) {
      if (Duration(seconds: syncAgeSeconds) < maxAge) {
        return Future<InternetTimeSyncResult>.value(success);
      }
    }
    return sync();
  }

  /// Arms the 15-minute background resync. Idempotent; safe to call from a
  /// resume handler as well as from `main`.
  ///
  /// The tick only schedules network work — [sync] never throws, so a tick on a
  /// dead network is a no-op that leaves the last good anchor in place.
  void startAutoResync() {
    if (_resyncTimer != null) return;
    _resyncTimer = Timer.periodic(autoResyncInterval, (_) {
      unawaited(sync(force: true));
    });
  }

  /// Stops the resync timer. The anchor is kept: a paused app that comes back to
  /// the same internet time should not have to re-prove it before its first
  /// frame is usable.
  void stopAutoResync() {
    _resyncTimer?.cancel();
    _resyncTimer = null;
  }

  /// [InternetTimeService.sync] must never throw, and the sampling code below
  /// is full of arithmetic on values that arrive from the network. This wrapper
  /// is the guarantee: any unexpected failure becomes an ordinary failed result.
  Future<InternetTimeSyncResult> _runSyncSafely() async {
    try {
      return await _runSync();
    } catch (error, stack) {
      debugPrint('InternetTimeService: sync threw ($error)');
      debugPrintStack(stackTrace: stack);
      const result = InternetTimeSyncResult(
        ok: false,
        error: 'Could not read the internet time. Check the phone\'s '
            'connection (mobile data or Wi-Fi) and try again.',
      );
      _lastResult = result;
      return result;
    }
  }

  Future<InternetTimeSyncResult> _runSync() async {
    await _loadCacheOnce();

    final samples = <_TimeSample>[];

    // HTTPS in parallel: three HEAD requests cost about as long as the slowest
    // one, and a sample is only useful if it arrives promptly.
    final httpsResults = await Future.wait(
      _httpsSources.map(_sampleHttps),
      eagerError: false,
    );
    for (final sample in httpsResults) {
      if (sample != null) samples.add(sample);
    }

    // SNTP only when HTTPS did not produce a quorum. Two agreeing sources is
    // what makes a median meaningful, so the fallback also runs when just one
    // HTTPS source answered.
    if (samples.length < 2) {
      final ntpResults = await Future.wait(
        _ntpHosts.map(_sampleNtp),
        eagerError: false,
      );
      for (final sample in ntpResults) {
        if (sample != null) samples.add(sample);
      }
    }

    if (samples.isEmpty) {
      debugPrint('InternetTimeService: no source answered');
      const result = InternetTimeSyncResult(
        ok: false,
        error: 'Could not read the internet time. Check the phone\'s '
            'connection (mobile data or Wi-Fi) and try again.',
      );
      _lastResult = result;
      return result;
    }

    final anchorElapsedMicros = _monotonic.elapsedMicroseconds;

    // Every sample describes a slightly different moment. Project all of them
    // onto the anchor instant using the monotonic clock, so the median is a
    // median of measurements of *the same instant* rather than of several
    // different ones.
    final projected = <DateTime>[
      for (final sample in samples)
        sample.instant.add(
          Duration(microseconds: anchorElapsedMicros - sample.elapsedMicros),
        ),
    ]..sort();

    final anchor = _medianDateTime(projected);

    final offsets = <int>[for (final sample in samples) sample.offsetMs]..sort();
    final medianOffsetMs = _medianInt(offsets);

    // Accuracy: how far the sources disagree with the chosen instant, plus the
    // half round trip of the slowest one. Both are real uncertainty, and the
    // answer is not more precise than their sum.
    var spreadMs = 0;
    for (final instant in projected) {
      final delta = instant.difference(anchor).inMilliseconds.abs();
      if (delta > spreadMs) spreadMs = delta;
    }
    var halfRttMs = 0;
    for (final sample in samples) {
      final half = sample.roundTripMs ~/ 2;
      if (half > halfRttMs) halfRttMs = half;
    }

    _httpsCount = samples.where((sample) => !sample.isNtp).length;
    _ntpCount = samples.where((sample) => sample.isNtp).length;
    _sourceCount = samples.length;
    _accuracyMs = spreadMs + halfRttMs;
    _deviceDriftSeconds = (medianOffsetMs / 1000).round();
    _contributingSources = <String>[for (final sample in samples) sample.source];

    // The anchor, and the monotonic reading it belongs to. From here on nothing
    // the user does to the device clock can move [now].
    _anchorInternet = anchor;
    _anchorElapsedMicros = anchorElapsedMicros;
    _syncElapsedMicros = anchorElapsedMicros;
    _lastSyncAt = DateTime.now();

    _startTicker();

    final result = InternetTimeSyncResult(
      ok: true,
      internetTime: now(),
      sourceCount: _sourceCount,
      sourceLabel: sourceLabel,
      accuracyMs: _accuracyMs,
      deviceDriftSeconds: _deviceDriftSeconds,
    );
    _lastResult = result;
    _lastSuccess = result;

    // Published last, so a listener that reads the service on the tick already
    // sees the new anchor.
    _ticker.value = now();

    unawaited(_persist(medianOffsetMs));
    return result;
  }

  /// One HTTPS sample. Returns null (never throws) on any failure.
  Future<_TimeSample?> _sampleHttps(String url) async {
    final client = http.Client();
    try {
      final stopwatch = Stopwatch()..start();
      final request = http.Request('HEAD', Uri.parse(url))
        ..headers['Cache-Control'] = 'no-cache'
        ..headers['Pragma'] = 'no-cache'
        ..headers['User-Agent'] = 'PPHLAttendance/2.5 (Android; Flutter)';

      final response = await client.send(request).timeout(_httpsTimeout);
      // A HEAD carries no body, but the exchange is not complete until the
      // stream is drained — draining is what makes the stopwatch measure the
      // whole round trip.
      await response.stream.drain<void>().timeout(_httpsTimeout);
      stopwatch.stop();

      final header = response.headers['date'];
      if (header == null || header.isEmpty) return null;

      DateTime serverInstant;
      try {
        // RFC 1123 (`Wed, 21 Oct 2015 07:28:00 GMT`); HttpDate also accepts the
        // two obsolete formats a few old proxies still emit.
        serverInstant = HttpDate.parse(header).toUtc();
      } catch (_) {
        return null;
      }

      return _sampleFromInstant(
        source: url,
        serverInstant: serverInstant,
        roundTripMicros: stopwatch.elapsedMicroseconds,
        isNtp: false,
        // An HTTP `Date` header is truncated to the second, so the value we
        // parsed is on average half a second *before* the instant it describes.
        // Compensating here is what makes an HTTPS sample and an NTP sample
        // (which carries 32 bits of fraction) agree to within a few tens of
        // milliseconds instead of a few hundred.
        truncationCompensationMicros: Duration.microsecondsPerMillisecond * 500,
      );
    } catch (error) {
      debugPrint('InternetTimeService: $url unavailable ($error)');
      return null;
    } finally {
      client.close();
    }
  }

  /// One SNTP sample over UDP 123. Returns null (never throws) on any failure.
  ///
  /// A 48-byte NTPv4 client packet is sent to the host's address and the reply's
  /// *transmit* timestamp is treated the same way as an HTTPS `Date` header:
  /// moved forward by half the measured round trip to get the instant it
  /// describes. The originate field is not verified — some servers zero it, and
  /// no other peer can reach this socket anyway, because the OS only delivers
  /// datagrams belonging to the 4-tuple we opened.
  Future<_TimeSample?> _sampleNtp(String host) async {
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    try {
      // Resolved before the stopwatch starts: DNS is not part of the exchange
      // this sample measures.
      final address = await _resolveNtpHost(host);
      if (address == null) return null;

      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final completer = Completer<Uint8List?>();

      subscription = socket.listen((event) {
        if (event != RawSocketEvent.read || completer.isCompleted) return;
        final data = socket?.receive()?.data;
        if (data == null || data.length < 48) return;
        completer.complete(data);
      });

      final packet = _buildNtpRequest();
      final stopwatch = Stopwatch()..start();
      final sent = socket.send(packet, address, _ntpPort);
      if (sent != packet.length) return null;

      final data = await completer.future.timeout(_ntpTimeout);
      stopwatch.stop();
      if (data == null) return null;

      // Leap indicator 3 means "clock not synchronised": the server is telling
      // us its own time is unreliable.
      if ((data[0] >> 6) == 3) return null;
      // Mode 4 is a server reply. Anything else (a stray client packet, a
      // broadcast) is not an answer to this request.
      if ((data[0] & 0x7) != 4) return null;

      // Seconds since the NTP epoch, plus the 32-bit fraction of a second.
      // A value from the next era (after 2036) reads as a date in the past and
      // is rejected by the sanity window rather than silently trusted.
      final seconds = _readUint32(data, 40);
      final fraction = _readUint32(data, 44);
      final serverInstant = DateTime.utc(1900, 1, 1).add(
        Duration(
          seconds: seconds,
          microseconds: (fraction * 1000000) ~/ 0x100000000,
        ),
      );

      return _sampleFromInstant(
        source: '$host (NTP)',
        serverInstant: serverInstant,
        roundTripMicros: stopwatch.elapsedMicroseconds,
        isNtp: true,
      );
    } catch (error) {
      debugPrint('InternetTimeService: NTP $host unavailable ($error)');
      return null;
    } finally {
      await subscription?.cancel();
      socket?.close();
    }
  }

  /// Turns a source's clock reading plus a measured round trip into a sample,
  /// rejecting values that cannot be a real clock (see [_sanityWindow]).
  _TimeSample? _sampleFromInstant({
    required String source,
    required DateTime serverInstant,
    required int roundTripMicros,
    required bool isNtp,
    int truncationCompensationMicros = 0,
  }) {
    final deviceNow = DateTime.now().toUtc();
    if (serverInstant.difference(deviceNow).abs() > _sanityWindow) {
      debugPrint(
        'InternetTimeService: $source returned an implausible time '
        '(${serverInstant.toIso8601String()}), ignoring it',
      );
      return null;
    }

    final halfTrip = Duration(microseconds: roundTripMicros ~/ 2);
    // The reply was generated half a round trip before it arrived, so the
    // source's clock at *our* midpoint is its stamp plus half the trip; the
    // device clock at that same midpoint is now minus half the trip. The
    // difference is the drift, measured on one clock's terms.
    final instant = serverInstant
        .add(halfTrip)
        .add(Duration(microseconds: truncationCompensationMicros));
    final deviceAtMidpoint = deviceNow.subtract(halfTrip);

    return _TimeSample(
      instant: instant,
      offsetMs: instant.difference(deviceAtMidpoint).inMilliseconds,
      roundTripMs: roundTripMicros ~/ 1000,
      elapsedMicros: _monotonic.elapsedMicroseconds,
      source: source,
      isNtp: isNtp,
    );
  }

  Future<InternetAddress?> _resolveNtpHost(String host) async {
    try {
      final addresses = await InternetAddress.lookup(host).timeout(_ntpTimeout);
      for (final address in addresses) {
        if (address.type == InternetAddressType.IPv4) return address;
      }
      return addresses.isEmpty ? null : addresses.first;
    } catch (error) {
      debugPrint('InternetTimeService: could not resolve $host ($error)');
      return null;
    }
  }

  /// A 48-byte SNTPv4 client request: leap 0, version 4, mode 3, with our own
  /// clock in the transmit field. The server copies that field into *originate*
  /// and fills *transmit* with its own time.
  Uint8List _buildNtpRequest() {
    final packet = Uint8List(48);
    packet[0] = 0x23; // 00 (no leap warning) | 100 (v4) | 011 (client)
    _writeNtpTimestamp(packet, 40, DateTime.now().toUtc());
    return packet;
  }

  void _writeNtpTimestamp(Uint8List buffer, int offset, DateTime time) {
    final sinceEpoch = time.difference(DateTime.utc(1900, 1, 1));
    final seconds = sinceEpoch.inSeconds & 0xFFFFFFFF;
    final microsInSecond = sinceEpoch.inMicroseconds % Duration.microsecondsPerSecond;
    final fraction =
        ((microsInSecond * 0x100000000) ~/ Duration.microsecondsPerSecond) &
            0xFFFFFFFF;
    _writeUint32(buffer, offset, seconds);
    _writeUint32(buffer, offset + 4, fraction);
  }

  static void _writeUint32(Uint8List buffer, int offset, int value) {
    buffer[offset] = (value >> 24) & 0xFF;
    buffer[offset + 1] = (value >> 16) & 0xFF;
    buffer[offset + 2] = (value >> 8) & 0xFF;
    buffer[offset + 3] = value & 0xFF;
  }

  static int _readUint32(Uint8List buffer, int offset) {
    return (buffer[offset] << 24) |
        (buffer[offset + 1] << 16) |
        (buffer[offset + 2] << 8) |
        buffer[offset + 3];
  }

  static DateTime _medianDateTime(List<DateTime> sorted) {
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    final lower = sorted[middle - 1].microsecondsSinceEpoch;
    final upper = sorted[middle].microsecondsSinceEpoch;
    return DateTime.fromMicrosecondsSinceEpoch(
      lower + ((upper - lower) ~/ 2),
      isUtc: true,
    );
  }

  static int _medianInt(List<int> sorted) {
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return sorted[middle - 1] + ((sorted[middle] - sorted[middle - 1]) ~/ 2);
  }

  void _startTicker() {
    if (_tickerTimer != null) return;
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isSynced) return;
      _ticker.value = now();
    });
  }

  /// Reads the persisted offset/epoch once, for display only. Deliberately does
  /// not touch [isSynced] or the anchor.
  Future<void> _loadCacheOnce() async {
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    try {
      final epochRaw = await _secureStorage.read(key: _syncEpochKey);
      final offsetRaw = await _secureStorage.read(key: _offsetKey);
      final epochMs = int.tryParse(epochRaw ?? '');
      if (epochMs != null && epochMs > 0) {
        _cachedSyncAt = DateTime.fromMillisecondsSinceEpoch(epochMs);
      }
      final offsetMs = int.tryParse(offsetRaw ?? '');
      if (offsetMs != null) _cachedDriftSeconds = (offsetMs / 1000).round();
    } catch (error) {
      debugPrint('InternetTimeService: could not read the cached sync ($error)');
    }
  }

  Future<void> _persist(int offsetMs) async {
    try {
      await _secureStorage.write(key: _offsetKey, value: '$offsetMs');
      await _secureStorage.write(
        key: _syncEpochKey,
        value: '${DateTime.now().millisecondsSinceEpoch}',
      );
      _cachedSyncAt = DateTime.now();
      _cachedDriftSeconds = (offsetMs / 1000).round();
    } catch (error) {
      debugPrint('InternetTimeService: could not persist the sync ($error)');
    }
  }

  /// One line for a log or a debug screen. Never parsed, never shown as a clock.
  String get debugSummary => isSynced
      ? 'internet=${now().toIso8601String()} '
          'drift=${deviceDriftSeconds}s accuracy=${accuracyMs}ms '
          'sources=$sourceLabel [${_contributingSources.join(', ')}]'
      : 'not synced (cached=${_cachedSyncAt?.toIso8601String() ?? 'none'})';

  @override
  String toString() => 'InternetTimeService($debugSummary)';
}
