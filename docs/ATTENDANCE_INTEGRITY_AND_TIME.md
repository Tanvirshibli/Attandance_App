# Attendance integrity and internet time

Status: implemented in the Flutter app (`lib/services/*`, `lib/widgets/integrity_guard.dart`)
and in the Android host (`MainActivity.kt`).

This document covers two things that are really one thing: **what the app trusts
before it will file an attendance punch**, and **what it does when that trust is
broken**.

Until now the punch path trusted the device clock and never asked whether the
position came from a spoofing app. Both are user-controlled settings on an
Android phone, which means an employee standing in a market could punch in "on
time" at the office, and the app had no way to tell.

---

## 1. The parts

| File | Job |
| --- | --- |
| `lib/services/internet_time_service.dart` | A clock that does not come from the phone. Median of 3 HTTPS `Date` headers, SNTP fallback, anchored to a monotonic counter. |
| `lib/services/device_integrity_service.dart` | The rules. `checkPosition()` and `checkTime()` return an `IntegrityViolation` or `null`. |
| `lib/services/integrity_lock_service.dart` | The lock. Publishes a violation, reports it, persists it, and clears it only for a real password sign-in. |
| `lib/services/integrity_api_service.dart` | Fire-and-forget reporting to `POST /api/v1/mobile/integrity-events`. |
| `lib/widgets/integrity_guard.dart` | The full-screen, non-dismissible overlay mounted above the Navigator. |
| `MainActivity.kt` (Kotlin) | `isMockLocationEnabled`, `isEmulator`, `isAdbEnabled` on method channel `com.pphl.attendance/device_integrity`. |

Nothing here changes the face or fingerprint paths. The biometric method channel
is registered by `BiometricKeystoreChannel` exactly as before; the integrity
channel is a separate registration in `MainActivity.configureFlutterEngine`.

---

## 2. Internet time

### Why not just `DateTime.now()`

`DateTime.now()` reads a setting. Settings can be changed from the notification
shade in four taps, and every "I was on time" dispute becomes unanswerable. So
the app fetches the time from somewhere else, and then keeps its own copy of it.

### Finding internet time

Three independent HTTPS endpoints are asked for the `Date` response header:

```
https://www.google.com
https://www.cloudflare.com
https://www.microsoft.com
```

For each one:

1. `t0` — start a `Stopwatch` (monotonic, not the wall clock).
2. Send a `HEAD` request and drain the response.
3. `t1` — stop the stopwatch.
4. The server generated its `Date` header roughly half a round trip before the
   reply arrived, so `instant = headerInstant + (t1 - t0) / 2`.
5. `offset = instant - deviceClockAtMidpoint`, which is only ever used to
   derive drift and the anchor.

`Date` is parsed as RFC 1123 (with the two obsolete formats `HttpDate` also
accepts). Second precision is all the header carries; the round-trip correction
is what makes that useful.

**The answer is the median of the successful samples**, not the first or the
mean. One slow or lying source cannot move a median of three, and the spread
across the samples plus half of the slowest round trip becomes `accuracyMs`.

### SNTP fallback

If fewer than two HTTPS sources answer, plain SNTP over UDP 123 is tried against
`time.google.com` and `pool.ntp.org`:

* a 48-byte NTPv4 client packet (leap 0, version 4, mode 3) with our clock in the
  transmit field,
* a 4-second timeout per host, resolved with `InternetAddress.lookup` before the
  stopwatch starts (DNS is not part of the measurement),
* the reply's **transmit** timestamp (bytes 40–47, 1900 epoch, 32-bit seconds +
  32-bit fraction) is treated exactly like a `Date` header,
* replies with leap indicator 3 ("clock not synchronised") or a mode other than
  4 are ignored,
* a reply further than a year from the device clock is rejected. That single
  check also covers the 2036 NTP era overflow, which would otherwise read as a
  date in 1968.

No pub package is used. `RawDatagramSocket` is enough.

### Freezing it — the important part

Every sync stores two values:

```
_anchorInternet         // DateTime, UTC
_anchorElapsedMicros    // reading of a process-wide Stopwatch
```

and `now()` is **always**:

```dart
_anchorInternet + (_monotonic.elapsedMicroseconds - _anchorElapsedMicros)
```

A `Stopwatch` counts real elapsed time and cannot be changed by the user. So
after the first sync, the device clock can be moved forward, moved back, frozen
or set to 1970, and `now()` does not follow it. The measured offset is never
re-applied after the anchor is taken — that is the difference between "we
checked the clock once" and "the clock cannot be moved under us".

Samples are projected onto the common anchor instant with the same monotonic
counter before the median is taken, so three replies that arrive 400 ms apart
are still three measurements of one moment.

### Failure behaviour

* `sync()` **never throws**. It always returns an `InternetTimeSyncResult` with
  `ok`, and on failure an `error` sentence a human can act on
  ("Could not read the internet time. Check the phone's connection…").
* Airplane mode is just the "no samples" case.
* `now()` **throws `StateError`** if this process has never synced. It never
  silently returns the device clock — a caller that cannot show a trustworthy
  time must refuse the action, and callers check `isSynced` first.
* The last offset and sync epoch are persisted in `flutter_secure_storage` so a
  cold start can *display* what the previous session found. `isSynced` stays
  false until a live sync succeeds in this process, because applying a stale
  offset to a clock that has since been moved would produce a confident, wrong,
  "verified" timestamp.

### Cadence

* `startAutoResync()` arms a 15-minute `Timer.periodic` (`main.dart` calls it).
* `syncIfStale()` is for app-resume and screen-open hooks. It returns the
  existing result when the anchor is younger than `maxAge` (default 15 min).
  `IntegrityGuard` calls it with a 60-second window on every resume, because a
  phone in a pocket has been asleep.
* Syncs closer together than 45 s are collapsed, and a sync already in flight is
  shared by every caller, so a resume plus a screen build plus a timer tick cost
  one round of requests.
* `ticker` (a `ValueNotifier<DateTime>`) emits every second while synced, and
  immediately after each sync.

### The one caveat worth knowing

Android's `CLOCK_MONOTONIC` — which is what `Stopwatch` reads — **stops counting
while the device is in deep sleep**, while the RTC keeps going. So between a
suspend and the next sync, `now()` can lag real time by the sleep duration. Two
things bound the damage:

* `syncAgeSeconds` is the **maximum** of elapsed monotonic time and elapsed
  device wall-clock time, so a suspension makes the anchor look old and forces a
  resync. Taking the max can only over-report the age, and over-reporting costs
  one round of HEAD requests.
* `IntegrityGuard` resyncs on every resume when the anchor is more than 60 s old,
  which is exactly when a suspend has happened.

Between those two, a punch is never stamped from an anchor that survived a sleep
without a re-read, unless the device is offline — in which case there is no
internet clock to read and the caller is expected to say so.

---

## 3. The rules

`DeviceIntegrityService.instance.checkPosition(Position)` runs, in order:

| Rule | Threshold | Type |
| --- | --- | --- |
| Fix flagged by the OS | `Position.isMocked` | `gps_mock` |
| Fix too coarse to place a site | `accuracy > 100 m` | `gps_untrusted` |
| No real fix | `lat == 0 && lng == 0` | `gps_untrusted` |
| Impossible travel | `> 200 km/h` and `> 0.5 km` since the baseline fix | `implausible_jump` |

**Never blocking — diagnostics only.** The phone's own mock-location settings
are read and reported with every event under `detail.mockDiagnostics`
(`opMode`, `providerPackage`, `adbEnabled`), but they cannot raise a violation:

* `AppOpsManager.OPSTR_MOCK_LOCATION` defaults to *allowed* for an app's own uid
  on many ROMs, so `checkOpNoThrow` reports "allowed" on a phone where nobody
  ever selected a mock app.
* `Settings.Secure["mock_location"]` commonly holds the literal `"0"` once a
  provider is cleared, so "non-empty" is not "a provider is set".

Both were used as a blocking test in the first release and locked honest phones
whose developer options had never been enabled. Only a fix that Android itself
flags (`Position.isMocked`) may block a punch. `IntegrityType.mockLocationApp`
stays in the enum for wire compatibility but no rule returns it, and a lock
persisted by an older build is dropped on upgrade
(`IntegrityLockService.isRetiredFalsePositive`).

`checkTime()` runs:

| Rule | Threshold | Type |
| --- | --- | --- |
| Clock differs from internet time | `|deviceDriftSeconds| > 60` | `time_drift` |
| Clock moved mid-session | `> 90 s` between one-second samples | `clock_jump` |

Design notes:

* **One violation at a time.** The first rule broken is returned; one clear
  instruction beats four stacked ones, and the overlay has room for exactly one.
* **The teleport baseline is a rolling window.** The first accepted fix becomes
  the reference. It moves forward at most every 10 s, so fixes arriving at 1 Hz
  do not turn ordinary ±30 m jitter into a "jump", while 200 km/h over a 10 s
  window still covers 555 m — comfortably above the 0.5 km floor.
* **A spoofed fix never becomes the baseline.** After an `implausible_jump` the
  old reference is kept.
* **Clock jumps need a short gap.** Android's monotonic clock stops counting
  while the device is asleep; the RTC does not. Comparing across a suspension
  would fire on every resume, so samples more than 5 s apart (monotonic) are
  treated as a resume and re-anchored silently. A clock change in the background
  is caught by `time_drift` on the next sync instead, which is the stronger
  signal anyway.
* **`checkTime()` returns `null` when nothing has synced.** A phone in a
  basement should not be locked out for a clock nobody could check. The caller is
  expected to show "time not verified" on its own.
* Messages name the exact measurement *and* the fix, e.g.
  *"You appear to have moved 3.2 km in 12 s — an average of 960 km/h since the
  last fix. No phone travels that fast, so one of the two positions is not real.
  Turn off any mock location or GPS-spoofing app, wait a few seconds, then try
  again."* Every raw number also goes into `violation.detail` for the backend and
  for support.
* `resetForNewSession()` clears the teleport baseline, any pending clock-jump
  finding and the native cache. It runs on a fresh password sign-in, so a shared
  phone never judges one employee's first fix against another's last one.

### Emulator exemption — and why it exists

```dart
// device_integrity_service.dart
static const bool _allowEmulatorSpoof =
    bool.fromEnvironment('ALLOW_EMULATOR_SPOOF');
```

Both conditions must hold: the native `isEmulator` heuristics say "emulator"
(`Build.FINGERPRINT` / `Build.HARDWARE` / `Build.MODEL`) **and** the build was
compiled with `--dart-define=ALLOW_EMULATOR_SPOOF=true`. When both are true, the
mock and teleport checks are skipped.

Reason: an emulator reports **every** position as a mock fix, and it cannot
physically move between two sites. Without the exemption the punch flow cannot be
exercised at all off a physical phone — including the FCM/geo-workmanager paths
that have historically only failed on a real device.

Two deliberate limits keep it from becoming a hole:

1. It is a **compile-time** flag. A production build (no `--dart-define`) ignores
   the emulator answer entirely, so a wrong heuristic cannot weaken a shipped
   APK, and a shipped APK cannot be talked into the exemption at runtime.
2. **Time checks are never exempted.** A device clock can be wrong on an emulator
   exactly as easily as on a phone, and the clock is the thing attackers actually
   want to change.

---

## 4. The lock

`IntegrityLockService`:

```dart
Future<void> raise(IntegrityViolation v);      // publish, report, persist
Future<bool> unlockWithPassword({required String email, required String password});
Future<void> restore();                        // boot: re-apply if < 24 h old
Future<bool> get isLocked;                     // async getter, memory or keystore
ValueNotifier<IntegrityViolation?> get violation;
```

* `raise()` sets the notifier **first and synchronously**, so the overlay is
  already covering the app before the (unawaited) report and the keystore write
  finish. Persistence is what survives a restart; it is not a precondition for
  locking.
* The flag, the violation JSON and the raise timestamp go into
  `flutter_secure_storage` (`integrity_lock_active`, `integrity_lock_violation`,
  `integrity_lock_raised_at`).
* `restore()` re-applies a persisted lock only when it is **younger than 24 h**
  (`restoreWindow`). A phone that sat in a drawer over the weekend does not come
  back locked for something already fixed. A negative age — the clock moved
  backwards — keeps the lock: that is itself suspicious, and a password clears
  it.
* `unlockWithPassword()` calls the existing `AuthService.login()` and clears the
  notifier **only on success**. On success it also calls
  `DeviceIntegrityService.resetForNewSession()` and force-refreshes internet
  time, so the session starts from a clean, verified state.
* Why a password at all: everything these rules detect is something the user can
  turn off and then carry on spoofing from a clean state. Clearing the lock costs
  the account password — the one thing somebody pretending to be at work does not
  have — and it can never strand an employee, because anyone who can open the app
  on that phone can also fix the device.

### The overlay

`IntegrityGuard` is mounted in `MaterialApp.builder`, **outside** `LocationGuard`
and `ConnectivityGuard`. Ordering matters: those two sheets describe states the
user can also create (turn location off, turn Wi-Fi off), so a tampering gate
placed inside them could be buried. The lock wins.

* Opaque `ColoredBox` (not a scrim, not a blur): it absorbs hit tests as well as
  covering the screen, and the child below is `IgnorePointer`ed.
* `PopScope(canPop: false)` and no dismiss affordance. The only interactive
  element is the compact email + password form, with a spinner and an inline
  error.
* The child stays mounted in slot 0 of the `Stack` (same shape as
  `ConnectivityGuard`) so a lock landing mid-form does not throw away what the
  user typed.
* Shows the violation title, the exact message, `violation.fixHint` ("how to
  fix"), and the device identifier from `DeviceIdentityService`.
* Colours are resolved explicitly (light card in a light theme, `darkSurface` in
  a dark one), so it stays legible in both; it is wrapped in a transparency
  `Material` because it is mounted above the Navigator and inherits no text
  style from a `Scaffold`.
* When no violation exists it is a pass-through: it never touches the login
  screen's own password flow.

---

## 5. What the backend receives

`POST {base}/api/v1/mobile/integrity-events` for every candidate in
`AppConfig.authApiBaseUrlCandidates`, with `Authorization: Bearer <token>` when a
session exists. `404` is treated as "this host does not serve the endpoint" and
the next candidate is tried.

```json
{
  "type": "time_drift",
  "detail": {
    "driftSeconds": -312,
    "toleranceSeconds": 60,
    "deviceTime": "2026-05-04T09:12:00.000",
    "internetTime": "2026-05-04T09:17:12.000Z",
    "internetTimeSource": "3 HTTPS sources",
    "internetTimeAccuracyMs": 118
  },
  "deviceIdentifier": "android-4f2c9a1e",
  "deviceName": "Android Attendance App",
  "clientInternetTime": "2026-05-04T09:17:12.000Z",
  "deviceTime": "2026-05-04T09:12:00.000"
}
```

`type` values: `gps_mock`, `gps_untrusted`, `implausible_jump`, `time_drift`,
`clock_jump`, `mock_location_app`.

`clientInternetTime` is **null** when nothing has synced — the backend must be
able to tell "the app has no internet clock" from "the internet clock said
09:12".

Reporting is telemetry, not enforcement: enforcement already happened on the
device. Every failure here — no network, no token, a backend that has not
deployed the endpoint yet — is logged and dropped. A report that cannot be sent
must never become a second, unrelated reason somebody cannot clock in.

---

## 6. Native channel

Channel `com.pphl.attendance/device_integrity`, registered in
`MainActivity.configureFlutterEngine` next to the battery channel. The biometric
channel registration is untouched.

| Method | Returns | Notes |
| --- | --- | --- |
| `isMockLocationEnabled` | `bool` | `AppOpsManager.checkOpNoThrow(OPSTR_MOCK_LOCATION, myUid, packageName) == MODE_ALLOWED`, **or** a non-empty `Settings.Secure["mock_location"]` provider (the literal string `"null"` some ROMs store counts as empty). |
| `isEmulator` | `bool` | `FINGERPRINT` starts with `generic` / contains `emulator`; `HARDWARE` contains `goldfish` / `ranchu`; `MODEL` contains `sdk` / `emulator`. Only used for the emulator exemption. |
| `isAdbEnabled` | `bool` | `Settings.Global.ADB_ENABLED`. Informational, copied into the event detail. |

Every native call is answered "no" on failure, on a non-Android platform and on
a build without the channel. A missing method must never block an honest punch.
Answers are cached for 5 s so the user can turn a mock-location app off between
attempts without a channel round trip per position update.

---

## 7. Known limits

* `Date` headers are second-precision. `accuracyMs` is typically 50–300 ms after
  the round-trip correction — irrelevant next to a 60 s drift tolerance.
* A rooted device with a modified kernel can lie about `SystemClock.elapsedRealtime`
  as well. Nothing in an app can defend against that; the backend still sees the
  `clientInternetTime` per event and can refuse punches.
* ISO 8601 timestamps: `deviceTime` is local-with-no-offset (`DateTime.now()`
  default), `clientInternetTime` is UTC with `Z`. Stated explicitly because it is
  easy to get wrong on the backend side.
* `dart:io` sockets are used for SNTP, so the fallback does not exist on web.
  Android only in practice.
* No pub packages were added.

---

## 8. Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Punch blocked, "Could not read the internet time" | Nothing has ever synced | Connect and retry; `syncIfStale()` runs on resume |
| Punch blocked, "clock is 312 seconds behind internet time" | Device clock is wrong | Settings → Date & time → *Automatic date and time* |
| Lock appears on launch, form rejects the password | Genuine bad password, or the host is unreachable | The form reports both the same way; check the connection |
| Everything blocked on an emulator | This is a production-style build | Build with `--dart-define=ALLOW_EMULATOR_SPOOF=true` |
| `now()` throws `StateError` | Called before the first sync | Check `isSynced` first; that is the contract |

---

## 9. Public API (for screens and services)

```dart
// lib/services/internet_time_service.dart
InternetTimeService.instance
  Future<InternetTimeSyncResult> sync({bool force = false});   // never throws
  Future<InternetTimeSyncResult> syncIfStale({Duration maxAge = 15 min});
  DateTime now();                       // UTC; StateError if never synced
  bool    get isSynced;
  bool    get isHealthy;                // synced and <= 5 minutes old
  int     get syncAgeSeconds;           // -1 when never synced
  int     get deviceDriftSeconds;       // internet - device clock
  int     get accuracyMs;
  int     get sourceCount;
  String  get sourceLabel;
  DateTime? get lastSyncAt;             // device time of the last live sync
  DateTime? get cachedSyncAt;           // persisted, previous process
  int?    get cachedDriftSeconds;       // persisted, previous process
  ValueNotifier<DateTime> get ticker;   // 1 Hz, UTC
  void startAutoResync();  void stopAutoResync();

// lib/services/device_integrity_service.dart
DeviceIntegrityService.instance
  Future<IntegrityViolation?> checkPosition(Position position);
  Future<IntegrityViolation?> checkTime();
  void    resetForNewSession();
  void    startMonitoring();
  Future<bool> get isEmulator;
  IntegrityViolation? get pendingViolation;

// lib/services/integrity_lock_service.dart
IntegrityLockService.instance
  ValueNotifier<IntegrityViolation?> get violation;
  IntegrityViolation? get current;
  Future<void> raise(IntegrityViolation violation);
  Future<bool> unlockWithPassword({required String email, required String password});
  Future<void> restore();
  Future<bool> get isLocked;
  Future<String?> savedEmail();
```

`IntegrityViolation` carries `type` (`IntegrityType`), `title`, `message`,
`detail`, a `fixHint` for the lock screen, and `toJson()` / `fromJson()` for
persistence.
