class AttendanceSummary {
  const AttendanceSummary({
    this.presentCount = 0,
    this.leaveCount = 0,
    this.absentCount = 0,
    this.holidayCount = 0,
    this.totalDays = 0,
    this.parsedFromKnownShape = false,
  });

  final int presentCount;
  final int leaveCount;
  final int absentCount;
  final int holidayCount;
  final int totalDays;

  /// True when [fromJson] recognized a `summary` object or `rows` list.
  final bool parsedFromKnownShape;

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

    for (final row in rows) {
      if (row is! Map) continue;
      final type = (row['attendanceType'] ?? row['attendance_type'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
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

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
