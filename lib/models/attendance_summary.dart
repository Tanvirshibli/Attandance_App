import 'attendance_classifier.dart';

class AttendanceSummary {
  const AttendanceSummary({
    this.presentCount = 0,
    this.leaveCount = 0,
    this.absentCount = 0,
    this.holidayCount = 0,
    this.totalDays = 0,
    this.parsedFromKnownShape = false,
    this.dayTypes = const {},
    this.rowPunchDays = const {},
    this.holidaysUnknown = false,
    this.rowsUnknown = false,
  });

  final int presentCount;
  final int leaveCount;
  final int absentCount;
  final int holidayCount;
  final int totalDays;

  /// True when [fromJson] recognized a `summary` object or `rows` list.
  final bool parsedFromKnownShape;

  /// Calendar day → normalized lowercase attendance type, built from
  /// daily `rows` (see [fromDailyRows]). Empty for other sources.
  final Map<DateTime, String> dayTypes;

  /// Calendar days HRM reported an in/out punch for, whatever its type said.
  ///
  /// The daily rows carry `inTime`/`outTime` beside `attendanceType`, and the
  /// type is frequently null on a day that clearly has punches (the backend only
  /// fills it when a detail row exists). Reading the type alone therefore made a
  /// worked day look unevidenced once the local punch list missed it, which is
  /// how Present under-reported and Absent over-reported.
  final Set<DateTime> rowPunchDays;

  /// True when the holiday calendar could not be loaded for this window.
  ///
  /// The counts are then not trustworthy for holidays: the screen must show a
  /// dash rather than present a number that silently counted those days as
  /// absences.
  final bool holidaysUnknown;

  /// True when HRM's daily rows could not be loaded for this window.
  final bool rowsUnknown;

  bool get hasAnyKpi =>
      presentCount > 0 ||
      leaveCount > 0 ||
      absentCount > 0 ||
      holidayCount > 0;

  factory AttendanceSummary.fromJson(Map<String, dynamic> json) {
    // Team / nested summary shape.
    final summary = json['summary'];
    if (summary is Map<String, dynamic>) {
      return AttendanceSummary(
        presentCount: _toInt(summary['presentCount'] ?? summary['present_count']),
        leaveCount: _toInt(summary['leaveCount'] ?? summary['leave_count']),
        absentCount: _toInt(summary['absentCount'] ?? summary['absent_count']),
        holidayCount:
            _toInt(summary['holidayCount'] ?? summary['holiday_count']),
        totalDays: _toInt(summary['totalDays'] ?? summary['total_days']),
        parsedFromKnownShape: true,
      );
    }

    // Unwrap HRM envelope: { message, data: { rows, totals } }.
    Map<String, dynamic> payload = json;
    final nested = json['data'];
    if (nested is Map<String, dynamic>) {
      payload = nested;
    }

    final rows = payload['rows'];
    if (rows is List) {
      return AttendanceSummary.fromDailyRows(rows);
    }

    // Unrecognized shape — caller may fall back to local estimates.
    return const AttendanceSummary(parsedFromKnownShape: false);
  }

  /// Counts Present / Absent / Leave / Holiday from single-employee daily rows.
  factory AttendanceSummary.fromDailyRows(List<dynamic> rows) {
    var present = 0;
    var absent = 0;
    var leave = 0;
    var holiday = 0;
    final dayTypes = <DateTime, String>{};
    final rowPunchDays = <DateTime>{};

    for (final row in rows) {
      if (row is! Map) continue;
      final type = (row['attendanceType'] ?? row['attendance_type'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

      final rawDate = row['date'] ?? row['attendance_date'] ?? row['attDate'];
      final parsedDate = DateTime.tryParse(rawDate?.toString() ?? '');
      if (parsedDate != null) {
        dayTypes[DateTime(parsedDate.year, parsedDate.month, parsedDate.day)] =
            type;

        // A row with an in or out timestamp is attendance evidence on its own.
        // The type can be null on a punched day, so it is counted separately
        // and only used when it says nothing about the day.
        final hasPunch = _hasTimestamp(row['inTime']) ||
            _hasTimestamp(row['in_time']) ||
            _hasTimestamp(row['outTime']) ||
            _hasTimestamp(row['out_time']);
        if (hasPunch) {
          rowPunchDays.add(
            DateTime(parsedDate.year, parsedDate.month, parsedDate.day),
          );
        }
      }

      if (type.isEmpty) continue;

      if (type.contains('present') || type == 'p') {
        present++;
      } else if (type.contains('absent') || type == 'a') {
        absent++;
      } else if (type.contains('leave') || type == 'l') {
        leave++;
      } else if (type.contains('holiday') || type == 'h') {
        holiday++;
      }
    }

    final counted = present + absent + leave + holiday;
    return AttendanceSummary(
      presentCount: present,
      leaveCount: leave,
      absentCount: absent,
      holidayCount: holiday,
      totalDays: counted > 0 ? counted : rows.length,
      parsedFromKnownShape: true,
      dayTypes: dayTypes,
      rowPunchDays: rowPunchDays,
    );
  }

  /// Builds the KPI counts from an already-decided classification.
  ///
  /// This factory does no deciding of its own: every day has already been put
  /// in exactly one bucket by [classifyDays], so the counts are read straight
  /// off the classification's getters and [totalDays] is its
  /// [AttendanceClassification.countedDays]. That keeps `absent` from being
  /// double-counted against a punch, a holiday or an approved leave — the bug
  /// [reconciledWithPunchDays] could only patch after the fact.
  ///
  /// [dayTypes] is carried through untouched so callers that render a per-day
  /// strip keep the HRM row types alongside the counts. [parsedFromKnownShape]
  /// defaults to `true` because a classification is a known shape even when its
  /// inputs were partly empty.
  factory AttendanceSummary.fromClassification(
    AttendanceClassification classification, {
    Map<DateTime, String> dayTypes = const {},
    Set<DateTime> rowPunchDays = const {},
    bool parsedFromKnownShape = true,
    bool holidaysUnknown = false,
    bool rowsUnknown = false,
  }) {
    return AttendanceSummary(
      presentCount: classification.presentCount,
      leaveCount: classification.leaveCount,
      absentCount: classification.absentCount,
      holidayCount: classification.holidayCount,
      totalDays: classification.countedDays,
      parsedFromKnownShape: parsedFromKnownShape,
      dayTypes: dayTypes,
      rowPunchDays: rowPunchDays,
      holidaysUnknown: holidaysUnknown,
      rowsUnknown: rowsUnknown,
    );
  }

  /// Moves punched days out of `absent` into `present`.
  ///
  /// Mobile punches live in the ZKTeco backend, not in HRM tables, so a
  /// punched day can come back as `absent` in the daily rows. [punchDays]
  /// holds calendar days with a non-rejected check-in or check-out.
  ///
  /// Per punch day inside the rows' coverage window:
  /// - `absent`/`a` → absent−1, present+1
  /// - missing from rows or untyped → present+1
  /// - any other type (`present`, `leave`, `holiday`, …) → unchanged
  ///
  /// When there is no per-day data at all (local fallbacks, `summary`
  /// objects) the counts are already consistent and this returns `this`.
  ///
  /// Superseded by [AttendanceClassification] applied through
  /// `AttendanceStatsService`: that path decides every day's bucket once (rows,
  /// punches, holidays, leave, weekly off) instead of only shifting `absent`
  /// into `present` on punched days. This method is kept unchanged only for
  /// callers that have not migrated yet — do not add new call sites.
  AttendanceSummary reconciledWithPunchDays(Set<DateTime> punchDays) {
    if (punchDays.isEmpty || dayTypes.isEmpty) return this;

    DateTime? firstDay;
    DateTime? lastDay;
    for (final day in dayTypes.keys) {
      if (firstDay == null || day.isBefore(firstDay)) firstDay = day;
      if (lastDay == null || day.isAfter(lastDay)) lastDay = day;
    }

    var present = presentCount;
    var absent = absentCount;

    for (final raw in punchDays) {
      final day = DateTime(raw.year, raw.month, raw.day);
      // Punches outside the rows' window are not represented here.
      if (day.isBefore(firstDay!) || day.isAfter(lastDay!)) continue;

      final type = dayTypes[day];
      if (type == null || type.isEmpty) {
        present++;
      } else if (type.contains('absent') || type == 'a') {
        if (absent > 0) absent--;
        present++;
      }
      // Any non-absent type already counts the day correctly.
    }

    final counted = presentCount + leaveCount + absentCount + holidayCount;
    return AttendanceSummary(
      presentCount: present,
      leaveCount: leaveCount,
      absentCount: absent,
      holidayCount: holidayCount,
      totalDays: totalDays == 0 || totalDays == counted
          ? present + absent + leaveCount + holidayCount
          : totalDays,
      parsedFromKnownShape: parsedFromKnownShape,
      dayTypes: dayTypes,
    );
  }

  /// Local estimate from punch requests when HRM summary rows are unavailable.
  factory AttendanceSummary.fromPunchRecords({
    required int presentDays,
    int absentDays = 0,
  }) {
    return AttendanceSummary(
      presentCount: presentDays,
      leaveCount: 0,
      absentCount: absentDays,
      holidayCount: 0,
      totalDays: presentDays + absentDays,
      parsedFromKnownShape: false,
    );
  }

  factory AttendanceSummary.fromRecords({
    required int approved,
    required int requested,
    required int rejected,
  }) {
    return AttendanceSummary(
      presentCount: approved,
      leaveCount: 0,
      absentCount: rejected,
      holidayCount: 0,
      totalDays: approved + requested + rejected,
      parsedFromKnownShape: false,
    );
  }

  /// True when a row field holds an actual timestamp.
  ///
  /// The backend blanks an absent punch to an empty string rather than null, so
  /// a plain `??` chain would treat `''` as present and stop before a real
  /// value on the other side. Both sides are therefore checked for content.
  static bool _hasTimestamp(Object? value) =>
      value != null && value.toString().trim().isNotEmpty;

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
