# Attendance UX pass (dashboard, transactions, stats)

This pass changed how the app reports backend work and how the dashboard
presents time. Nothing here changes the API contract.

## Transaction overlay

`TransactionUiService` (`lib/services/transaction_ui_service.dart`) publishes the
state of **user-initiated** work; `TransactionOverlay`
(`lib/widgets/transaction_overlay.dart`) paints it.

- A full-screen barrier with a large circular progress ring, centred, with the
  action's label underneath.
- On success the ring becomes a green disc with a tick; on failure a red disc
  with a cross. The barrier clears **2 seconds** after the outcome.
- The overlay is mounted inside `MaterialApp.builder`, **below** the integrity
  and location guards (a transaction must never hide a tampering lock) and
  **above** every route, so it survives the check-in screen popping.
- Exactly one transaction shows at a time; a second caller waits for the first
  to clear instead of stacking barriers.
- Wrapped actions: password login, biometric login, fingerprint enrolment and
  removal, punch submit (detached, reports on the dashboard after the camera
  closes), manual dashboard refresh.
- Background work stays silent on purpose: internet-time resync, geo pings, OTA
  check, silent token refresh and integrity reporting.
- The overlay is the only widget in the tree with no `Material` above it
  (`MaterialApp.builder` wraps the Navigator), so its contents are wrapped in
  `Material(type: MaterialType.transparency)`. Without that, Flutter paints the
  debug double yellow underline under every `Text` in the barrier.

## Dashboard card

- The clock is **12-hour** with a separate `AM`/`PM` suffix (`formatClock` /
  `formatMeridiem` are pure and unit-tested).
- Check-in and check-out times are the visual anchor: `CHECK-IN` / `CHECK-OUT`
  labels with 26 px bold, tabular figures, `--:--` when absent so the card does
  not jump.
- The assigned shift has its own block under the date ("ASSIGNED SHIFT" +
  name), and turns amber with "No shift assigned" when the profile has none.

## Method chooser

The face/fingerprint chooser is a centred dialog instead of a bottom sheet. Its
inputs are cached (`_faceRegistered`, `_fingerprintAvailable`), so the dialog
opens without awaiting the platform channel.

The tap path also matters: `_openCheckFlow` used to `await` a punch-list reload
before deciding what to offer, and that round-trip was the whole delay. The
guards now run on cached state (`_punchBlockReason`) so the dialog is the first
thing drawn, the reload runs concurrently, and the guards are re-evaluated after
the choice — before the camera opens — so a stale cache can never start a scan
for a punch the server will refuse.

## Fingerprint availability

Fingerprint options are only offered when `BiometricAuthService.availability()`
says the device can authenticate:

- dashboard chooser omits the Fingerprint option,
- Profile hides both fingerprint switches and the enrol/remove row,
- login keeps password and face only.

A check that *fails* is treated as "available" so a platform hiccup never hides
a working setting.

## Absent and holiday figures

- An **open today** is no longer counted as an absence
  (`AttendanceStatsService.withoutOpenTodayAbsence`); a punched, leave or holiday
  day still counts.
- If the holiday calendar cannot be loaded, the summary is marked
  `holidaysUnknown` and the Holiday tile shows `—` instead of a number inflated
  by treating holidays as absences. A failed HRM row fetch marks `rowsUnknown`
  and does the same for Absent.
- Dashboard, history and report still share one calculation
  (`AttendanceStatsService` / `AttendanceClassifier`), so they cannot disagree.
