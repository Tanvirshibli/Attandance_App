class AttendanceSummary {
  const AttendanceSummary({
    this.presentCount = 0,
    this.leaveCount = 0,
    this.absentCount = 0,
    this.holidayCount = 0,
    this.totalDays = 0,
  });

  final int presentCount;
  final int leaveCount;
  final int absentCount;
  final int holidayCount;
  final int totalDays;

  factory AttendanceSummary.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'];
    if (summary is Map<String, dynamic>) {
      return AttendanceSummary(
        presentCount: _toInt(summary['presentCount']),
        leaveCount: _toInt(summary['leaveCount']),
        absentCount: _toInt(summary['absentCount']),
        holidayCount: _toInt(summary['holidayCount']),
        totalDays: _toInt(summary['totalDays']),
      );
    }
    return const AttendanceSummary();
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
    );
  }

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
