import 'package:intl/intl.dart';

/// Verdict for a self check-in attempt: refused, or still inside the grace
/// period.
class CheckInWindowResult {
  const CheckInWindowResult({
    required this.isClosed,
    this.deadline,
    this.message,
  });

  /// Whether the shift start (plus the grace period) has already passed.
  final bool isClosed;

  /// The last instant at which a check-in is still accepted — the shift start
  /// plus [CheckInWindow.graceMinutes], rolled back a day for a night shift.
  /// Null whenever the shift start is unknown, because no deadline was derived.
  final DateTime? deadline;

  /// Employee-facing refusal, worded identically to the server's so the two
  /// sides read the same. Null unless [isClosed].
  final String? message;
}

/// Decides whether a self check-in is still inside the company's grace window.
///
/// This is a deliberate contract twin of the server-side guard in
/// `pphl_erp/app/Http/Controllers/Api/MobileAttendanceController.php` —
/// `CHECK_IN_GRACE_MINUTES` (:266), the refusal guard (:191-199) and the
/// message builder (:280-308). The server stays the authority and re-checks
/// every punch; this class exists so the app can refuse *before* the camera
/// opens instead of letting the employee scan a face and be rejected after it.
/// Keep the two in step: if the grace period or the wording changes there, it
/// changes here too.
///
/// It fails open. `GET /api/v1/get-my-info` only carries `shift_start_time`
/// when HRM actually holds a shift row for the employee, and the endpoint's
/// contract (`UserController.php:320-328`) is that the app keeps working
/// without one. Turning "HR has no rota for me" into a lock-out would strand
/// employees on the days it matters most, so an absent, blank, `'null'` or
/// unparseable start leaves the window open and lets the server decide.
class CheckInWindow {
  const CheckInWindow._();

  /// Mirrors `MobileAttendanceController::CHECK_IN_GRACE_MINUTES`.
  static const int graceMinutes = 15;

  /// Above this, a deadline is assumed to belong to the previous day: a 23:00
  /// shift started *yesterday*, so at 00:02 its deadline is 1h in the past, not
  /// 23h in the future.
  static const Duration _nightShiftRollbackThreshold = Duration(hours: 12);

  static final RegExp _timePattern = RegExp(
    r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$',
  );

  static CheckInWindowResult evaluate({
    required String? shiftStartTime,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final start = _parseShiftStart(shiftStartTime, current);
    if (start == null) {
      return const CheckInWindowResult(isClosed: false);
    }

    var deadline = start.add(const Duration(minutes: graceMinutes));
    if (deadline.difference(current) > _nightShiftRollbackThreshold) {
      deadline = deadline.subtract(const Duration(days: 1));
    }

    // The backend refuses only when `now > deadline`, so punching exactly on
    // the deadline still counts as on time.
    if (!current.isAfter(deadline)) {
      return CheckInWindowResult(isClosed: false, deadline: deadline);
    }

    final formattedStart = DateFormat('h:mm a').format(start);
    return CheckInWindowResult(
      isClosed: true,
      deadline: deadline,
      message:
          'Check-in is closed. Your shift started at $formattedStart and the '
          '$graceMinutes-minute grace period has passed.',
    );
  }

  /// Anchors the bare `HH:mm[:ss]` HRM time column to [now]'s local date.
  ///
  /// Returns null for anything unusable so [evaluate] can fail open rather than
  /// guess a shift that HR never supplied.
  static DateTime? _parseShiftStart(String? shiftStartTime, DateTime now) {
    final text = shiftStartTime?.trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }

    final match = _timePattern.firstMatch(text);
    if (match == null) {
      return null;
    }

    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    final second = int.tryParse(match.group(3) ?? '0');
    if (hour == null ||
        minute == null ||
        second == null ||
        hour > 23 ||
        minute > 59 ||
        second > 59) {
      return null;
    }

    return DateTime(now.year, now.month, now.day, hour, minute, second);
  }
}
