import 'package:flutter/foundation.dart';

import '../models/attendance_classifier.dart';
import '../models/attendance_request_record.dart';
import '../models/attendance_summary.dart';
import 'attendance_calendar_service.dart';
import 'attendance_report_service.dart';

/// The single place a month's attendance KPIs are decided.
///
/// Three independent sources feed the month strip and the KPI header:
///
/// * HRM daily rows ([AttendanceReportService.getSummary]) — the office's own
///   opinion of each day (`present`, `absent`, `leave`, …).
/// * Punch requests ([AttendanceRequestRecord]) — what this phone actually
///   recorded. Punches live in the ZKTeco backend, so HRM rows routinely miss
///   them (or still say `absent` for a day the employee clearly punched).
/// * The calendar ([AttendanceCalendarService]) — holidays and approved
///   leave, plus the weekly-off predicate.
///
/// Deciding the counts in one service (rather than re-deriving them per screen)
/// is what keeps the KPI header, the day strip and the summary card agreeing
/// with each other: screens hand in their punch records and read back an
/// [AttendanceSummary], and the precedence rules live in exactly one file.
class AttendanceStatsService {
  AttendanceStatsService({
    AttendanceReportService? reportService,
    AttendanceCalendarService? calendarService,
  })  : _reportService = reportService ?? AttendanceReportService(),
        _calendarService = calendarService ?? AttendanceCalendarService.instance;

  /// Shared instance for screens. A caller that needs a fake report or calendar
  /// service (tests, a one-off preview) builds its own instance instead.
  static final AttendanceStatsService instance = AttendanceStatsService();

  final AttendanceReportService _reportService;
  final AttendanceCalendarService _calendarService;

  /// Loads the month KPIs for [employeeId] over `[from, to]`.
  ///
  /// [punchRecords] are the employee's punch requests for roughly the same
  /// window; rejected requests and rows with no check-in *and* no check-out are
  /// ignored, because neither represents work. A row with only one side of the
  /// punch does count: the employee turned up.
  ///
  /// The two network calls are issued together — the holiday/leave calendar
  /// can be slow (it pages the leave list) and must not serialise in front of
  /// the KPI load, which is what the screen waits on.
  ///
  /// Nothing here throws:
  /// * a failed summary fetch degrades to "no known row types", so every day is
  ///   decided by the punch set and the calendar alone;
  /// * a failed calendar fetch degrades to "no holidays, no approved leave";
  /// * `employeeId <= 0` (profile not loaded yet) skips the summary request
  ///   entirely and classifies from punches plus the calendar, since asking HRM
  ///   for employee 0 only produces a pointless round-trip.
  Future<AttendanceSummary> load({
    required int employeeId,
    required DateTime from,
    required DateTime to,
    required Iterable<AttendanceRequestRecord> punchRecords,
  }) async {
    final punchDays = _punchDays(punchRecords);

    // Start both requests before awaiting either one. `(a, b).wait` is the
    // typed equivalent of `Future.wait`: it overlaps them and hands back a
    // record, so no cast is needed. Both futures below already swallow their
    // own failures, so this cannot raise `ParallelWaitError`.
    final (summaryRows, calendar) = await (
      _loadSummary(employeeId: employeeId, from: from, to: to),
      _loadCalendar(employeeId: employeeId, from: from, to: to),
    ).wait;

    // Empty when the fetch failed: an unknown row type must not outvote a
    // punch, so classification falls through to the punch/calendar rules.
    final rowTypes = summaryRows?.dayTypes ?? const <DateTime, String>{};

    final classification = classifyDays(
      days: _dayWindow(from: from, to: to),
      rowTypes: rowTypes,
      punchDays: punchDays,
      holidayDays: calendar.holidays,
      approvedLeaveDays: calendar.approvedLeaveDays,
      isWeeklyOff: isDefaultWeeklyOff,
    );

    return AttendanceSummary.fromClassification(
      classification,
      dayTypes: rowTypes,
    );
  }

  /// Calendar days that carry a real punch — rejected rows and empty rows are
  /// skipped, and everything is normalised to a date-only day so a punch at
  /// 23:55 and a row dated the same day collapse into one entry.
  static Set<DateTime> _punchDays(Iterable<AttendanceRequestRecord> records) {
    final days = <DateTime>{};
    for (final record in records) {
      if (record.isRejected) continue;
      // Neither side punched: the row is a request stub, not attendance.
      if (!record.hasCheckIn && !record.hasCheckOut) continue;

      final day = record.effectiveCalendarDay;
      if (day == null) continue;
      days.add(calendarDay(day));
    }
    return days;
  }

  /// Every calendar day in `[from, to]`, clipped at today.
  ///
  /// A future day has not happened yet, so counting it would invent absences
  /// from the moment the month is opened. Today *is* included and passed
  /// through untouched — whether an unpunched in-progress day is an absence
  /// is the classifier's decision, not this service's.
  ///
  /// The loop steps with `DateTime(y, m, day + 1)` rather than
  /// `add(Duration(days: 1))`: a DST transition is 23 or 25 hours long, and a
  /// duration step can skip or repeat a calendar day.
  static List<DateTime> _dayWindow({
    required DateTime from,
    required DateTime to,
  }) {
    final today = calendarDay(DateTime.now());
    final start = calendarDay(from);
    var end = calendarDay(to);
    if (end.isAfter(today)) end = today;

    final days = <DateTime>[];
    for (var day = start;
        !day.isAfter(end);
        day = DateTime(day.year, day.month, day.day + 1)) {
      days.add(day);
    }
    return days;
  }

  /// HRM daily rows, or `null` when they are unavailable for any reason.
  Future<AttendanceSummary?> _loadSummary({
    required int employeeId,
    required DateTime from,
    required DateTime to,
  }) async {
    if (employeeId <= 0) return null;

    try {
      final result = await _reportService.getSummary(
        employeeId: employeeId,
        from: from,
        to: to,
      );
      if (!result.success || result.data == null) {
        debugPrint(
          'AttendanceStatsService: summary unavailable '
          '(${result.message ?? 'no data'}) — classifying from punches only.',
        );
        return null;
      }
      return result.data;
    } catch (error) {
      debugPrint('AttendanceStatsService._loadSummary failed: $error');
      return null;
    }
  }

  /// Holidays and approved leave for the window, or an empty calendar.
  Future<AttendanceCalendar> _loadCalendar({
    required int employeeId,
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      return await _calendarService.load(
        employeeId: employeeId,
        from: from,
        to: to,
      );
    } catch (error) {
      // Without the calendar an approved leave day can look like an absence and
      // a holiday like an absent day, but a KPI load must never fail a screen.
      debugPrint('AttendanceStatsService._loadCalendar failed: $error');
      return const AttendanceCalendar();
    }
  }
}
