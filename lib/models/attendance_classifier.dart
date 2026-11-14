/// One calendar day's bucket. Exactly one applies.
///
/// The monthly view used to count a day twice (or zero times): a Saturday
/// inside a leave request, or a public holiday that came back as `absent` from
/// HRM, was still subtracted from the payable-day denominator. Bucketing every
/// day into exactly one of these values keeps the counters summing back to the
/// number of days the company actually worked, which is what the screens and
/// the payroll export assume.
enum DayBucket {
  /// The employee was at work: a real punch exists, or HRM says present/late.
  present,

  /// Nothing accounts for the day: no punch, no leave, no holiday, not a
  /// weekly off. This is the fallback bucket and must never be "no bucket".
  absent,

  /// Approved leave covers the day.
  leave,

  /// Public / declared holiday from the holiday calendar.
  holiday,

  /// The company does not work that weekday (Fri+Sat by default). Excluded
  /// from the countable-day denominator, see
  /// [AttendanceClassification.countedDays].
  weeklyOff,
}

/// Inputs for a single day.
///
/// All the evidence about a day arrives from different systems (HRM daily rows,
/// the ZKTeco punch log, the leave service, the holiday calendar) and none of
/// them is authoritative on its own. Keeping them as independent flags instead
/// of pre-merging them lets [classifyDay] decide, in one documented order, which
/// signal wins — the merge itself was the source of the double counting.
class DayInput {
  const DayInput({
    required this.day,
    this.rowType = '',
    this.punched = false,
    this.holiday = false,
    this.approvedLeave = false,
  });

  final DateTime day;

  /// Lowercased `attendanceType` from HRM, may be ''.
  final String rowType;

  /// Has a non-rejected check-in/out that day.
  final bool punched;

  /// Inside a holiday range from the holiday calendar.
  final bool holiday;

  /// Covered by an approved leave record.
  final bool approvedLeave;
}

/// True for a day the company does not work (default Fri+Sat).
///
/// Injected instead of hard-coded because a branch/shift can have a different
/// workweek, and because tests need to pin the rule without touching a clock.
typedef WeeklyOffPredicate = bool Function(DateTime day);

/// Classifies one day. First match wins — this is what guarantees exclusivity.
///
/// Precedence, and why it is this order:
/// 1. present — a real punch outranks everything. Someone who worked a holiday
///    or a Saturday must be credited present, otherwise the day is both
///    "worked" and "holiday/off" and the counts inflate.
/// 2. holiday — before leave so a leave request that spans a public holiday
///    does not consume leave for a day the company was closed anyway.
/// 3. leave — after holiday, before weekend, so a leave day is visible as leave
///    rather than being swallowed by the Fri+Sat rule.
/// 4. weeklyOff — after the explicit types so a row that says "present" on a
///    Saturday still counts as present; only unclaimed weekend days land here.
/// 5. absent — explicit `absent` as well as empty/unrecognised row types. The
///    fallback is deliberately "absent" rather than "skip": a day with no
///    evidence at all is a missed day, but it is still exactly one bucket, so
///    the totals can never exceed the number of days in the window.
///
/// [isWeeklyOff] is the already-resolved answer of a [WeeklyOffPredicate] for
/// `input.day`; [classifyDays] does that lookup, so a single call here stays
/// free of calendar policy.
DayBucket classifyDay(DayInput input, {required bool isWeeklyOff}) {
  // HRM sends mixed case, padded strings and sometimes a bare code, so compare
  // against a normalised form only.
  final rowType = input.rowType.trim().toLowerCase();

  if (input.punched ||
      rowType.contains('present') ||
      rowType.contains('late')) {
    return DayBucket.present;
  }

  if (input.holiday || rowType.contains('holiday') || rowType == 'h') {
    return DayBucket.holiday;
  }

  if (input.approvedLeave || rowType.contains('leave') || rowType == 'l') {
    return DayBucket.leave;
  }

  if (isWeeklyOff || rowType.contains('weekend') || rowType == 'w') {
    return DayBucket.weeklyOff;
  }

  // Explicit `absent`/`a`, an empty string, or a type we do not recognise.
  // Unknown values are treated as "no explicit type" on purpose: crediting an
  // unknown string as present would hide a genuine absence.
  return DayBucket.absent;
}

/// Result of classifying a window.
class AttendanceClassification {
  const AttendanceClassification(this.buckets);

  /// Calendar day -> bucket. Weekends are present here as [DayBucket.weeklyOff]
  /// but are left out of [countedDays].
  final Map<DateTime, DayBucket> buckets;

  int get presentCount => _count(DayBucket.present);

  int get absentCount => _count(DayBucket.absent);

  int get leaveCount => _count(DayBucket.leave);

  int get holidayCount => _count(DayBucket.holiday);

  int get weeklyOffCount => _count(DayBucket.weeklyOff);

  /// presentCount + absentCount + leaveCount + holidayCount (weekends excluded).
  int get countedDays => presentCount + absentCount + leaveCount + holidayCount;

  int _count(DayBucket bucket) =>
      buckets.values.where((value) => value == bucket).length;
}

/// Classifies every day in [days]. Keys are normalised via [calendarDay].
///
/// The evidence maps come from different sources that each key their dates
/// differently (HRM ISO timestamps, punch log dates, leave range expansion), so
/// every key is normalised here instead of trusting the callers to agree. Days
/// that repeat in [days] are classified once — the result is a map keyed by
/// calendar day, and re-classifying could only overwrite the same answer.
AttendanceClassification classifyDays({
  required Iterable<DateTime> days,
  required Map<DateTime, String> rowTypes,
  required Set<DateTime> punchDays,
  required Set<DateTime> holidayDays,
  required Set<DateTime> approvedLeaveDays,
  required WeeklyOffPredicate isWeeklyOff,
}) {
  // Collapse any time component in the evidence keys. When several keys land on
  // the same day the last one wins, which matches "latest row parsed wins" in
  // AttendanceSummary.dayTypes.
  final rowTypesByDay = <DateTime, String>{};
  rowTypes.forEach((key, value) {
    rowTypesByDay[calendarDay(key)] = value;
  });

  final punches = _calendarDays(punchDays);
  final holidays = _calendarDays(holidayDays);
  final leaves = _calendarDays(approvedLeaveDays);

  final buckets = <DateTime, DayBucket>{};
  for (final raw in days) {
    final day = calendarDay(raw);
    if (buckets.containsKey(day)) continue;

    buckets[day] = classifyDay(
      DayInput(
        day: day,
        // A missing entry means "no explicit type", not "unknown error".
        rowType: rowTypesByDay[day] ?? '',
        punched: punches.contains(day),
        holiday: holidays.contains(day),
        approvedLeave: leaves.contains(day),
      ),
      isWeeklyOff: isWeeklyOff(day),
    );
  }

  return AttendanceClassification(buckets);
}

/// Strips the time component: DateTime(y, m, d). Use for every key.
///
/// The local-time constructor (not [DateTime.utc]) is used so keys line up with
/// [DateTime] values built from the device calendar and with
/// `DateTime.tryParse` of a plain `yyyy-MM-dd` string.
DateTime calendarDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// Default weekly-off rule: Friday and Saturday.
///
/// Matches the Gulf workweek the HRM holiday table is configured for. Kept as a
/// standalone function so a branch with a different week can pass its own
/// [WeeklyOffPredicate] to [classifyDays].
bool isDefaultWeeklyOff(DateTime day) =>
    day.weekday == DateTime.friday || day.weekday == DateTime.saturday;

Set<DateTime> _calendarDays(Iterable<DateTime> values) =>
    values.map(calendarDay).toSet();
