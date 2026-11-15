import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import 'internet_time_service.dart';

/// What kind of tampering a violation describes.
///
/// [wireName] is what the backend receives; it is snake_case so the attendance
/// integrity feed groups cleanly with the rest of the mobile API's events.
enum IntegrityType {
  gpsMock('gps_mock'),
  gpsUntrusted('gps_untrusted'),
  implausibleJump('implausible_jump'),
  timeDrift('time_drift'),
  clockJump('clock_jump'),
  mockLocationApp('mock_location_app');

  const IntegrityType(this.wireName);

  final String wireName;

  static IntegrityType? fromWireName(String? name) {
    for (final value in IntegrityType.values) {
      if (value.wireName == name || value.name == name) return value;
    }
    return null;
  }
}

/// One detected integrity problem.
///
/// [message] is the whole point of this class: it names the exact measurement
/// that failed and the exact thing the user has to change, because a punch
/// that fails with "invalid request" teaches nobody anything. [detail] carries
/// the raw numbers for the backend and for support.
class IntegrityViolation {
  const IntegrityViolation({
    required this.type,
    required this.title,
    required this.message,
    this.detail = const <String, dynamic>{},
  });

  final IntegrityType type;

  /// One short line, for a sheet title or a log line.
  final String title;

  /// Plain English: what was detected, with the measured values, and the fix.
  final String message;

  /// Raw evidence. Serialised straight into the integrity event body, so every
  /// value must be JSON-encodable.
  final Map<String, dynamic> detail;

  String get wireName => type.wireName;

  /// The one-line instruction shown under [message] on the lock screen.
  String get fixHint => switch (type) {
        IntegrityType.gpsMock =>
          'Turn off the fake-GPS app, then sign in again.',
        IntegrityType.mockLocationApp =>
          'Developer options → turn off "Select mock location app".',
        IntegrityType.gpsUntrusted =>
          'Turn location on and wait for a good fix, then try again.',
        IntegrityType.implausibleJump =>
          'Turn off mock-location apps and stay still for a moment.',
        IntegrityType.timeDrift =>
          'Settings → Date & time → switch on "Automatic date and time".',
        IntegrityType.clockJump =>
          'Switch on "Automatic date and time" and stop changing the clock.',
      };

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type.wireName,
        'title': title,
        'message': message,
        'detail': detail,
      };

  static IntegrityViolation? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final type = IntegrityType.fromWireName(raw['type']?.toString());
    if (type == null) return null;
    final detailRaw = raw['detail'];
    return IntegrityViolation(
      type: type,
      title: raw['title']?.toString() ?? 'Attendance blocked',
      message: raw['message']?.toString() ??
          'This device failed an attendance integrity check.',
      detail: detailRaw is Map
          ? detailRaw.map((key, value) => MapEntry(key.toString(), value))
          : const <String, dynamic>{},
    );
  }

  @override
  String toString() => 'IntegrityViolation(${type.wireName}): $message';
}

/// Decides whether a position or a clock reading is trustworthy enough to
/// stamp an attendance punch with.
///
/// The two questions are deliberately separate — [checkPosition] and
/// [checkTime] — because the fix for each is different and the UI has to say
/// which one failed. Both return `null` when everything is fine, and a single
/// [IntegrityViolation] naming the *first* rule broken otherwise: one clear
/// instruction beats four stacked ones.
///
/// Session state
/// -------------
/// Two rules only make sense relative to earlier readings, so this service
/// remembers them for the life of the session:
///
/// * **Teleporting.** The first accepted fix is kept as the baseline; later
///   fixes are compared against it. The baseline moves forward at most every
///   [_baselineWindowSeconds], which is what stops ordinary GPS jitter (±30 m
///   while standing still) from being read as movement while still catching a
///   real jump: at 200 km/h a 10-second window still covers 555 m.
/// * **Clock jumps.** The device clock is compared against the monotonic clock
///   every second. See [_sampleClock].
///
/// Call [resetForNewSession] when a new user signs in, so one person's last fix
/// is never used to judge the next person's first one.
class DeviceIntegrityService {
  DeviceIntegrityService._() {
    _ensureMonitoring();
  }

  static final DeviceIntegrityService instance = DeviceIntegrityService._();

  /// The Android side lives in `MainActivity`, next to the battery channel.
  static const MethodChannel _channel =
      MethodChannel('com.pphl.attendance/device_integrity');

  /// Lets a harness or a demo build run on an emulator, where every fix is
  /// "mocked" by definition. Only honoured together with a real emulator
  /// detection — see [_gpsChecksSkipped].
  static const bool _allowEmulatorSpoof = bool.fromEnvironment(
    'ALLOW_EMULATOR_SPOOF',
  );

  /// A fix coarser than this cannot prove anybody is at an office; it is also
  /// the accuracy a phone reports indoors on a bad day, so the message tells the
  /// user to step outside rather than accusing them.
  static const double _maxAccuracyMetres = 100;

  /// Faster than any road vehicle, and the threshold the attendance policy
  /// documents.
  static const double _maxPlausibleSpeedKmh = 200;

  /// Below this the pair of fixes cannot distinguish real movement from jitter,
  /// so the speed is checked over a longer window instead.
  static const double _minJumpDistanceKm = 0.5;

  /// How often the teleport baseline is allowed to move forward.
  static const double _baselineWindowSeconds = 10;

  /// Tolerated difference between the phone's clock and internet time.
  static const int _driftToleranceSeconds = 60;

  /// A clock that moves this far between two one-second samples is being
  /// changed by somebody, not drifting.
  static const int _clockJumpToleranceSeconds = 90;

  /// A sample pair further apart than this is not a "tick" any more — the app
  /// was suspended, and a stopwatch on Android does not count suspended time
  /// while the RTC does. Judging that gap would fire on every resume.
  static const int _maxJumpSampleGapMs = 5000;

  /// Native answers are cheap but not free, and the user can turn a mock-location
  /// app off *between* attempts; a short TTL means a fix is noticed on the retry
  /// without a channel round trip per position update.
  static const Duration _nativeCacheTtl = Duration(seconds: 5);

  static final Stopwatch _monotonic = Stopwatch()..start();

  // --- Native checks -------------------------------------------------------

  bool? _emulator;
  bool? _mockLocationEnabled;
  bool? _adbEnabled;
  int _nativeCheckedAtMs = -1000000;

  // --- GPS session state ---------------------------------------------------

  _Fix? _baselineFix;

  // --- Clock session state -------------------------------------------------

  IntegrityViolation? _pendingClockJump;
  DateTime? _clockAnchorDevice;
  int _clockAnchorElapsedMs = 0;

  bool _monitoring = false;

  /// Starts watching the clock for changes. Idempotent, and safe to call before
  /// anything else.
  ///
  /// Every check also starts it, but a check only runs when somebody asks — and
  /// a clock changed at 10:00 and used at 17:00 leaves no evidence if nobody was
  /// sampling in between. `main.dart` calls this at startup so the window opens
  /// with the session. Sampling itself needs [InternetTimeService.ticker], which
  /// only ticks once internet time has synced.
  void startMonitoring() => _ensureMonitoring();

  /// Whether this device looks like an emulator (cached for the process).
  Future<bool> get isEmulator async {
    final cached = _emulator;
    if (cached != null) return cached;
    final value = await _invokeBool('isEmulator');
    _emulator = value;
    return value;
  }

  /// GPS rules, in the order the user should hear about them.
  ///
  /// Returns `null` when the fix is usable, which is also what a non-Android
  /// platform and a build with the channel missing get: a channel that is not
  /// there must not block attendance.
  Future<IntegrityViolation?> checkPosition(Position position) async {
    _ensureMonitoring();

    // Resolved before the rules so the exemption can consult it.
    final emulator = await isEmulator;
    if (_allowEmulatorSpoof && emulator) {
      // An emulator reports every fix as mocked and cannot physically move, so
      // these two rules would only ever block the harness. See
      // `docs/ATTENDANCE_INTEGRITY_AND_TIME.md`. Time checks are never
      // exempted: a clock can be wrong on an emulator as easily as on a phone.
      return null;
    }

    if (await _isMockLocationEnabled()) {
      return IntegrityViolation(
        type: IntegrityType.mockLocationApp,
        title: 'Mock location is switched on',
        message: 'A mock-location app is set as this phone\'s location '
            'provider, so the position sent with an attendance punch would not '
            'be where you actually are. Turn off "Select mock location app" in '
            'Developer options, then try again.',
        detail: <String, dynamic>{
          'mockLocationEnabled': true,
          'adbEnabled': await _isAdbEnabled(),
          'accuracyMetres': position.accuracy,
        },
      );
    }

    if (position.isMocked) {
      return IntegrityViolation(
        type: IntegrityType.gpsMock,
        title: 'Fake GPS detected',
        message: 'Android flagged this position as a mock fix, which means a '
            'fake-GPS app supplied it instead of the phone\'s own receiver. '
            'Turn off the fake-GPS app (and any developer "mock location" '
            'setting), then take the punch again.',
        detail: <String, dynamic>{
          'isMocked': true,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracyMetres': position.accuracy,
        },
      );
    }

    if (position.accuracy > _maxAccuracyMetres) {
      return IntegrityViolation(
        type: IntegrityType.gpsUntrusted,
        title: 'Location is too imprecise',
        message: 'This fix is only accurate to '
            '${position.accuracy.round()} m, and anything above '
            '${_maxAccuracyMetres.round()} m cannot show which site you are '
            'at. Step outside or near a window, wait for the location to '
            'settle, then try again.',
        detail: <String, dynamic>{
          'accuracyMetres': position.accuracy,
          'maxAccuracyMetres': _maxAccuracyMetres,
          'latitude': position.latitude,
          'longitude': position.longitude,
        },
      );
    }

    if (position.latitude == 0 && position.longitude == 0) {
      return IntegrityViolation(
        type: IntegrityType.gpsUntrusted,
        title: 'No real location fix',
        message: 'The phone reported 0, 0 as its position, which is what a GPS '
            'receiver returns when it has no fix at all — not a place on the '
            'map. Turn location on, wait for the pin to settle, then try '
            'again.',
        detail: <String, dynamic>{
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracyMetres': position.accuracy,
        },
      );
    }

    return _checkTeleport(position);
  }

  /// Time rules. Returns `null` when the phone's clock is trustworthy.
  ///
  /// Drift needs internet time, so this returns `null` when nothing has synced —
  /// a phone in a basement should not be locked out for a clock nobody could
  /// check. The caller is expected to say "time not verified" on its own.
  Future<IntegrityViolation?> checkTime() async {
    _ensureMonitoring();

    // Sampled here as well as on the ticker: the moment a punch is taken is
    // exactly the moment this has to be up to date, whether or not a tick
    // happened in the last second.
    _sampleClock();

    final jump = _pendingClockJump;
    if (jump != null) return jump;

    final time = InternetTimeService.instance;
    if (!time.isSynced) return null;

    final drift = time.deviceDriftSeconds;
    if (drift.abs() <= _driftToleranceSeconds) return null;

    final direction = drift > 0 ? 'behind' : 'ahead of';
    final magnitude = drift.abs();

    return IntegrityViolation(
      type: IntegrityType.timeDrift,
      title: 'This phone\'s clock is wrong',
      message: 'The phone\'s clock is $magnitude seconds (${_describeSeconds(magnitude)}) '
          '$direction internet time. A punch taken now would be filed at the '
          'wrong time, so it is on hold until the clock is right. Turn on '
          '"Automatic date and time" in the phone\'s settings, wait for the '
          'clock to correct itself, then try again.',
      detail: <String, dynamic>{
        'driftSeconds': drift,
        'toleranceSeconds': _driftToleranceSeconds,
        'deviceTime': DateTime.now().toIso8601String(),
        'internetTime': time.now().toIso8601String(),
        'internetTimeSource': time.sourceLabel,
        'internetTimeAccuracyMs': time.accuracyMs,
      },
    );
  }

  /// Forgets everything that belongs to the previous session: the teleport
  /// baseline, a pending clock-jump finding and the native cache.
  ///
  /// Called on a fresh password sign-in, so a shared phone never judges one
  /// employee's first fix against another's last one.
  void resetForNewSession() {
    _baselineFix = null;
    _pendingClockJump = null;
    _clockAnchorDevice = null;
    _clockAnchorElapsedMs = 0;
    _mockLocationEnabled = null;
    _adbEnabled = null;
    _nativeCheckedAtMs = -1000000;
  }

  /// The pending clock-jump finding, if the ticker caught one. Exposed so a
  /// screen can react between checks.
  IntegrityViolation? get pendingViolation => _pendingClockJump;

  IntegrityViolation? _checkTeleport(Position position) {
    final elapsedMs = _monotonic.elapsedMilliseconds;
    final baseline = _baselineFix;

    if (baseline == null) {
      _baselineFix = _Fix(position, elapsedMs);
      return null;
    }

    final seconds = (elapsedMs - baseline.elapsedMs) / 1000.0;
    if (seconds < 1) return null;

    final distanceKm = _distanceKm(
      baseline.latitude,
      baseline.longitude,
      position.latitude,
      position.longitude,
    );
    final speedKmh = distanceKm / (seconds / 3600.0);

    if (speedKmh > _maxPlausibleSpeedKmh && distanceKm > _minJumpDistanceKm) {
      // The baseline stays where it was: a spoofed fix must not become the
      // reference for the next one.
      return IntegrityViolation(
        type: IntegrityType.implausibleJump,
        title: 'Impossible movement',
        message: 'You appear to have moved ${distanceKm.toStringAsFixed(1)} km '
            'in ${seconds.round()} s — an average of '
            '${speedKmh.round()} km/h since the last fix. No phone travels that '
            'fast, so one of the two positions is not real. Turn off any mock '
            'location or GPS-spoofing app, wait a few seconds, then try again.',
        detail: <String, dynamic>{
          'distanceKm': double.parse(distanceKm.toStringAsFixed(3)),
          'elapsedSeconds': double.parse(seconds.toStringAsFixed(1)),
          'speedKmh': speedKmh.round(),
          'maxSpeedKmh': _maxPlausibleSpeedKmh,
          'fromLatitude': baseline.latitude,
          'fromLongitude': baseline.longitude,
          'toLatitude': position.latitude,
          'toLongitude': position.longitude,
        },
      );
    }

    // Rolling baseline: moved forward only once the window is old enough that
    // the next comparison still covers real distance, so a fix stream at 1 Hz
    // does not turn every pair into a 30-metre "jump".
    if (seconds >= _baselineWindowSeconds) {
      _baselineFix = _Fix(position, elapsedMs);
    }
    return null;
  }

  /// Compares the device clock against elapsed monotonic time.
  ///
  /// Runs on every [InternetTimeService.ticker] tick (one second while synced)
  /// and on every [checkTime] call. A gap longer than [_maxJumpSampleGapMs] is
  /// treated as a suspension, not a jump: Android's monotonic clock stops
  /// counting while the device is asleep, the RTC does not, so a resume would
  /// otherwise look like a two-hour clock jump.
  void _sampleClock() {
    final nowDevice = DateTime.now();
    final elapsedMs = _monotonic.elapsedMilliseconds;
    final anchorDevice = _clockAnchorDevice;

    if (anchorDevice != null) {
      final gapMs = elapsedMs - _clockAnchorElapsedMs;
      if (gapMs > 0 && gapMs <= _maxJumpSampleGapMs) {
        final expected = anchorDevice.add(Duration(milliseconds: gapMs));
        final deltaMs = nowDevice.difference(expected).inMilliseconds;
        if (deltaMs.abs() > _clockJumpToleranceSeconds * 1000) {
          final jumpSeconds = (deltaMs / 1000).round();
          _pendingClockJump = IntegrityViolation(
            type: IntegrityType.clockJump,
            title: 'The phone\'s clock was changed',
            message: 'The clock jumped ${_describeSeconds(jumpSeconds.abs())} '
                '${jumpSeconds > 0 ? 'forward' : 'back'} in '
                '${(gapMs / 1000).toStringAsFixed(1)} s of real time. '
                'Attendance times come from the internet clock, so nothing is '
                'recorded at the wrong time, but a phone whose clock is being '
                'changed cannot be trusted. Switch on "Automatic date and '
                'time", then sign in again.',
            detail: <String, dynamic>{
              'jumpSeconds': jumpSeconds,
              'elapsedSeconds': double.parse((gapMs / 1000).toStringAsFixed(1)),
              'deviceTime': nowDevice.toIso8601String(),
              'toleranceSeconds': _clockJumpToleranceSeconds,
            },
          );
        }
      }
    }

    // Re-anchored on every sample: the rule is "did the clock move relative to
    // real time *since the last sample*", which is what survives a slow clock
    // (caught by the drift rule instead) while catching a discrete change.
    _clockAnchorDevice = nowDevice;
    _clockAnchorElapsedMs = elapsedMs;
  }

  void _ensureMonitoring() {
    if (_monitoring) return;
    _monitoring = true;
    try {
      InternetTimeService.instance.ticker.addListener(_onTick);
    } catch (error) {
      debugPrint('DeviceIntegrityService: could not watch the clock ($error)');
    }
    _clockAnchorDevice = DateTime.now();
    _clockAnchorElapsedMs = _monotonic.elapsedMilliseconds;
  }

  void _onTick() => _sampleClock();

  Future<bool> _isMockLocationEnabled() async {
    await _refreshNativeIfStale();
    return _mockLocationEnabled ?? false;
  }

  Future<bool> _isAdbEnabled() async {
    await _refreshNativeIfStale();
    return _adbEnabled ?? false;
  }

  Future<void> _refreshNativeIfStale() async {
    final ageMs = _monotonic.elapsedMilliseconds - _nativeCheckedAtMs;
    if (ageMs >= 0 && ageMs < _nativeCacheTtl.inMilliseconds) return;
    _nativeCheckedAtMs = _monotonic.elapsedMilliseconds;

    // Both asked on one refresh, so the detail map always describes the same
    // moment as the verdict.
    _mockLocationEnabled = await _invokeBool('isMockLocationEnabled');
    _adbEnabled = await _invokeBool('isAdbEnabled');
  }

  /// Any native failure is "no signal", never "guilty": the channel is absent
  /// on iOS and on any host that was not updated with this build, and a missing
  /// method must not block a punch.
  Future<bool> _invokeBool(String method) async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      debugPrint('DeviceIntegrityService: $method failed (${error.code})');
      return false;
    } catch (error) {
      debugPrint('DeviceIntegrityService: $method failed ($error)');
      return false;
    }
  }

  static bool get _isAndroid {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  /// Great-circle distance in kilometres.
  static double _distanceKm(
    double fromLatitude,
    double fromLongitude,
    double toLatitude,
    double toLongitude,
  ) {
    const earthRadiusKm = 6371.0088;
    final dLat = _toRadians(toLatitude - fromLatitude);
    final dLon = _toRadians(toLongitude - fromLongitude);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(fromLatitude)) *
            math.cos(_toRadians(toLatitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180.0;

  /// `312` -> `5 min 12 s`. The raw seconds stay in [IntegrityViolation.detail];
  /// the message says both so a support agent and an employee read the same
  /// number.
  static String _describeSeconds(int seconds) {
    if (seconds < 60) return '$seconds s';
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    if (minutes < 60) {
      return remainder == 0 ? '$minutes min' : '$minutes min $remainder s';
    }
    final hours = minutes ~/ 60;
    final restMinutes = minutes % 60;
    return restMinutes == 0 ? '$hours h' : '$hours h $restMinutes min';
  }
}

/// One accepted fix, kept as the reference for the teleport check.
class _Fix {
  const _Fix(this.position, this.elapsedMs);

  final Position position;
  final int elapsedMs;

  double get latitude => position.latitude;
  double get longitude => position.longitude;
}
