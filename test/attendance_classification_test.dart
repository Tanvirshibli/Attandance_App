import 'package:employee_attendance/models/attendance_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for the attendance day classifier.
///
/// The regression these tests exist for: the app used to fold holidays,
/// approved leave and weekly offs into `absent`, so a single date showed up as
/// both a holiday and an absence in the monthly summary.
///
/// Fixtures are pinned to March 2025: 2025-03-01 is a Saturday, so 2025-03-03
/// is a Monday and the month holds 22 working days plus 9 weekly offs
/// (4 Fridays, 5 Saturdays). Nothing here reads the wall clock.

DateTime _march(int day) => DateTime(2025, 3, day);

DateTime _marchAt(int day, int hour, int minute) =>
    DateTime(2025, 3, day, hour, minute);

List<DateTime> _marchDays() =>
    List<DateTime>.generate(31, (index) => _march(index + 1));

bool _isWeekendDay(DateTime day) =>
    day.weekday == DateTime.friday || day.weekday == DateTime.saturday;

List<DateTime> _marchWorkingDays() =>
    _marchDays().where((day) => !_isWeekendDay(day)).toList();

/// A calendar with no weekly-off rule at all, so a test can isolate one source
/// of classification instead of colliding with the default Fri/Sat rule.
bool _noWeeklyOffs(DateTime day) => false;

int _totalBuckets(AttendanceClassification result) =>
    result.presentCount +
    result.absentCount +
    result.leaveCount +
    result.holidayCount +
    result.weeklyOffCount;

void main() {
  group('a holiday on a working Monday — the reported double count', () {
    // Risk: the summary adds the same date to the holiday total AND the
    // absence total, so a month where the employee respected a declared
    // holiday still reads as a missed day. Every assertion below is one that a
    // holiday-as-absent implementation cannot satisfy.
    final holidayMonday = _march(3); // Monday, an ordinary working day.
    final monthDays = _marchDays();
    final workingDays = _marchWorkingDays();
    final punchDays = workingDays.where((day) => day != holidayMonday).toSet();

    AttendanceClassification classifyHolidayMonth() => classifyDays(
      days: monthDays,
      rowTypes: <DateTime, String>{holidayMonday: 'absent'},
      punchDays: punchDays,
      holidayDays: <DateTime>{holidayMonday},
      approvedLeaveDays: const <DateTime>{},
      isWeeklyOff: isDefaultWeeklyOff,
    );

    test('reclassifies the HRM "absent" row on the holiday to holiday', () {
      final result = classifyHolidayMonth();

      expect(result.buckets[holidayMonday], DayBucket.holiday);
      expect(result.buckets[holidayMonday], isNot(DayBucket.absent));
    });

    test('reports one holiday and no absence for the same date', () {
      final result = classifyHolidayMonth();

      expect(result.holidayCount, 1);
      expect(result.absentCount, 0);
    });

    test('counts the holiday month as 22 days, not 23 and not 31', () {
      final result = classifyHolidayMonth();

      // Fixture guard: 31 calendar days, 9 of them weekly offs.
      expect(monthDays.length, 31);
      expect(punchDays.length, 21);

      expect(result.buckets.length, 31);
      expect(result.presentCount, 21);
      expect(result.countedDays, 22); // 21 punched working days + the holiday.
      expect(
        result.presentCount +
            result.absentCount +
            result.leaveCount +
            result.holidayCount,
        result.countedDays,
      );
    });
  });

  group('a holiday typed "absent" by HRM is still a holiday', () {
    // Risk: HRM exports its own row type for declared holidays. If the row type
    // outranks the holiday calendar the same date is reported twice — once as a
    // holiday from the calendar, once as an absence from the row.
    test('the holiday flag outranks an "absent" row type', () {
      expect(
        classifyDay(
          DayInput(day: _march(3), rowType: 'absent', holiday: true),
          isWeeklyOff: false,
        ),
        DayBucket.holiday,
      );
    });

    test('the holiday flag outranks every conflicting row type', () {
      for (final rowType in <String>[
        'absent',
        'a',
        'leave',
        'l',
        'weekend',
        'w',
        'not-marked',
      ]) {
        expect(
          classifyDay(
            DayInput(day: _march(3), rowType: rowType, holiday: true),
            isWeeklyOff: false,
          ),
          DayBucket.holiday,
          reason: 'rowType "$rowType" must not knock a holiday out of its bucket',
        );
      }
    });

    test('a "holiday" row type wins even without the holiday flag', () {
      for (final rowType in <String>['holiday', 'h', 'declared holiday']) {
        expect(
          classifyDay(
            DayInput(day: _march(3), rowType: rowType),
            isWeeklyOff: false,
          ),
          DayBucket.holiday,
          reason: 'rowType "$rowType" describes a holiday',
        );
      }
    });

    test('a "holiday" row type is enough inside a full month', () {
      final holidayMonday = _march(3);

      final result = classifyDays(
        days: _marchDays(),
        rowTypes: <DateTime, String>{holidayMonday: 'holiday'},
        punchDays: <DateTime>{},
        holidayDays: const <DateTime>{},
        approvedLeaveDays: const <DateTime>{},
        isWeeklyOff: isDefaultWeeklyOff,
      );

      expect(result.buckets[holidayMonday], DayBucket.holiday);
      expect(result.holidayCount, 1);
      expect(result.absentCount, 21); // the rest of the working days only.
    });
  });

  group('approved leave is not an absence', () {
    // Risk: an approved leave day with no punch looks exactly like an absence to
    // a naive counter, so employees are penalised for leave HR already granted.
    final leaveDay = _march(4); // Tuesday, a working day.

    test('an approved leave day with no punch classifies as leave', () {
      final result = classifyDays(
        days: <DateTime>[leaveDay],
        rowTypes: const <DateTime, String>{},
        punchDays: const <DateTime>{},
        holidayDays: const <DateTime>{},
        approvedLeaveDays: <DateTime>{leaveDay},
        isWeeklyOff: _noWeeklyOffs,
      );

      expect(result.buckets[leaveDay], DayBucket.leave);
      expect(result.leaveCount, 1);
      expect(result.absentCount, 0);
      expect(result.countedDays, 1);
    });

    test('an approved leave day typed "absent" by HRM stays leave', () {
      final result = classifyDays(
        days: <DateTime>[leaveDay],
        rowTypes: <DateTime, String>{leaveDay: 'absent'},
        punchDays: const <DateTime>{},
        holidayDays: const <DateTime>{},
        approvedLeaveDays: <DateTime>{leaveDay},
        isWeeklyOff: _noWeeklyOffs,
      );

      expect(result.buckets[leaveDay], DayBucket.leave);
      expect(result.absentCount, 0);
    });

    test('the approvedLeave flag alone classifies the day as leave', () {
      expect(
        classifyDay(
          DayInput(day: _march(4), approvedLeave: true),
          isWeeklyOff: false,
        ),
        DayBucket.leave,
      );
    });

    test('"leave" and "l" row types classify the day as leave', () {
      for (final rowType in <String>['leave', 'l', 'approved leave']) {
        expect(
          classifyDay(
            DayInput(day: _march(4), rowType: rowType),
            isWeeklyOff: false,
          ),
          DayBucket.leave,
          reason: 'rowType "$rowType" describes leave',
        );
      }
    });
  });

  group('weekly offs are not absences', () {
    // Risk: a Friday or Saturday with no punch was reported as an absence, so
    // every month carried four or five phantom absences nobody could explain.
    test('a Friday with no punch and no row is a weekly off', () {
      final friday = _march(7);

      final result = classifyDays(
        days: <DateTime>[friday],
        rowTypes: const <DateTime, String>{},
        punchDays: const <DateTime>{},
        holidayDays: const <DateTime>{},
        approvedLeaveDays: const <DateTime>{},
        isWeeklyOff: isDefaultWeeklyOff,
      );

      expect(result.buckets[friday], DayBucket.weeklyOff);
      expect(result.weeklyOffCount, 1);
      expect(result.absentCount, 0);
      expect(
        result.presentCount +
            result.absentCount +
            result.leaveCount +
            result.holidayCount,
        0, // weekly offs sit outside countedDays.
      );
    });

    test('the default week off is Friday and Saturday', () {
      expect(isDefaultWeeklyOff(_march(7)), isTrue, reason: 'Friday');
      expect(isDefaultWeeklyOff(_march(8)), isTrue, reason: 'Saturday');
      expect(isDefaultWeeklyOff(_march(3)), isFalse, reason: 'Monday');
      expect(isDefaultWeeklyOff(_march(2)), isFalse, reason: 'Sunday');
      expect(isDefaultWeeklyOff(_march(4)), isFalse, reason: 'Tuesday');
      expect(isDefaultWeeklyOff(_march(5)), isFalse, reason: 'Wednesday');
      expect(isDefaultWeeklyOff(_march(6)), isFalse, reason: 'Thursday');
    });

    test('an unpunched month reports 22 absences, not 31', () {
      final result = classifyDays(
        days: _marchDays(),
        rowTypes: const <DateTime, String>{},
        punchDays: const <DateTime>{},
        holidayDays: const <DateTime>{},
        approvedLeaveDays: const <DateTime>{},
        isWeeklyOff: isDefaultWeeklyOff,
      );

      expect(result.absentCount, 22); // 31 days minus 9 weekly offs.
      expect(result.weeklyOffCount, 9);
      expect(result.countedDays, 22);
      expect(result.buckets.length, 31);
    });

    test('a "weekend" or "w" row type marks a weekly off on any day', () {
      for (final rowType in <String>['weekend', 'w']) {
        expect(
          classifyDay(
            DayInput(day: _march(3), rowType: rowType),
            isWeeklyOff: false,
          ),
          DayBucket.weeklyOff,
          reason: 'rowType "$rowType" describes a weekly off',
        );
      }
    });
  });

  group('a punch always wins', () {
    // Risk: someone who works a holiday or a weekly off must be credited with
    // attendance, and the day must leave the holiday/weekly-off totals so the
    // summary stays exclusive.
    test('a punched holiday is present and leaves the holiday count', () {
      final holidayMonday = _march(3);

      final result = classifyDays(
        days: <DateTime>[holidayMonday],
        rowTypes: <DateTime, String>{holidayMonday: 'holiday'},
        punchDays: <DateTime>{holidayMonday},
        holidayDays: <DateTime>{holidayMonday},
        approvedLeaveDays: const <DateTime>{},
        isWeeklyOff: isDefaultWeeklyOff,
      );

      expect(result.buckets[holidayMonday], DayBucket.present);
      expect(result.presentCount, 1);
      expect(result.holidayCount, 0);
      expect(result.countedDays, 1);
    });

    test('a punch on a weekly off is present, not a weekly off', () {
      final saturday = _march(8);

      final result = classifyDays(
        days: <DateTime>[saturday],
        rowTypes: const <DateTime, String>{},
        punchDays: <DateTime>{saturday},
        holidayDays: const <DateTime>{},
        approvedLeaveDays: const <DateTime>{},
        isWeeklyOff: isDefaultWeeklyOff,
      );

      expect(result.buckets[saturday], DayBucket.present);
      expect(result.presentCount, 1);
      expect(result.weeklyOffCount, 0);
    });

    test('"present" and "late" row types count as present', () {
      for (final rowType in <String>['present', 'late']) {
        expect(
          classifyDay(
            DayInput(day: _march(4), rowType: rowType),
            isWeeklyOff: false,
          ),
          DayBucket.present,
          reason: 'rowType "$rowType" records a punch',
        );
      }
    });

    test('a punch outranks an "absent" row and approved leave', () {
      expect(
        classifyDay(
          DayInput(
            day: _march(4),
            rowType: 'absent',
            punched: true,
            approvedLeave: true,
          ),
          isWeeklyOff: false,
        ),
        DayBucket.present,
      );
    });
  });

  group('a multi-day holiday range counts each day once', () {
    // Risk: long holidays (festivals, shutdowns) were reported as one absence
    // per day. Each date in the range must land in the holiday bucket exactly
    // once, including the Friday that is also a weekly off.
    final range = List<DateTime>.generate(5, (index) => _march(3 + index));

    test('every day of the range is a holiday', () {
      final result = classifyDays(
        days: range,
        rowTypes: <DateTime, String>{for (final day in range) day: 'absent'},
        punchDays: const <DateTime>{},
        holidayDays: range.toSet(),
        approvedLeaveDays: const <DateTime>{},
        isWeeklyOff: isDefaultWeeklyOff,
      );

      for (final day in range) {
        expect(result.buckets[day], DayBucket.holiday, reason: '$day');
      }

      expect(result.holidayCount, 5);
      expect(result.absentCount, 0);
      expect(result.weeklyOffCount, 0); // holiday outranks the Friday off.
      expect(result.countedDays, 5);
      expect(result.buckets.length, 5);
      expect(_totalBuckets(result), 5);
    });
  });

  group('precedence — present > holiday > leave > weekly off > absent', () {
    // Risk: the four sources (punch log, holiday calendar, leave approvals,
    // weekly-off rule) overlap constantly. A day that lands in two buckets is
    // reported twice, which is exactly how the double count started.
    test('holiday outranks approved leave', () {
      final day = _march(4);

      expect(
        classifyDay(
          DayInput(day: day, holiday: true, approvedLeave: true),
          isWeeklyOff: false,
        ),
        DayBucket.holiday,
      );

      final result = classifyDays(
        days: <DateTime>[day],
        rowTypes: const <DateTime, String>{},
        punchDays: const <DateTime>{},
        holidayDays: <DateTime>{day},
        approvedLeaveDays: <DateTime>{day},
        isWeeklyOff: _noWeeklyOffs,
      );

      expect(result.buckets[day], DayBucket.holiday);
      expect(result.holidayCount, 1);
      expect(result.leaveCount, 0);
      expect(result.countedDays, 1);
    });

    test('holiday outranks a weekly off', () {
      final friday = _march(7);

      expect(
        classifyDay(DayInput(day: friday, holiday: true), isWeeklyOff: true),
        DayBucket.holiday,
      );
    });

    test('leave outranks a weekly off', () {
      final friday = _march(7);

      expect(
        classifyDay(
          DayInput(day: friday, approvedLeave: true),
          isWeeklyOff: true,
        ),
        DayBucket.leave,
      );

      final result = classifyDays(
        days: <DateTime>[friday],
        rowTypes: const <DateTime, String>{},
        punchDays: const <DateTime>{},
        holidayDays: const <DateTime>{},
        approvedLeaveDays: <DateTime>{friday},
        isWeeklyOff: isDefaultWeeklyOff,
      );

      expect(result.buckets[friday], DayBucket.leave);
      expect(result.leaveCount, 1);
      expect(result.weeklyOffCount, 0);
    });

    test('a weekly off outranks an "absent" row', () {
      expect(
        classifyDay(
          DayInput(day: _march(7), rowType: 'absent'),
          isWeeklyOff: true,
        ),
        DayBucket.weeklyOff,
      );
    });

    test('a punch outranks a holiday and approved leave together', () {
      expect(
        classifyDay(
          DayInput(
            day: _march(3),
            punched: true,
            holiday: true,
            approvedLeave: true,
          ),
          isWeeklyOff: true,
        ),
        DayBucket.present,
      );
    });
  });

  group('genuine absences are still reported', () {
    // Risk: "stop counting holidays as absences" must not slide into "never
    // report an absence". A past working day with no punch and no explanation
    // is a real absence and must stay visible.
    test('an empty row type on a past working day is an absence', () {
      final monday = _march(10);

      expect(
        classifyDay(DayInput(day: monday), isWeeklyOff: false),
        DayBucket.absent,
      );
      expect(
        classifyDay(DayInput(day: monday, rowType: ''), isWeeklyOff: false),
        DayBucket.absent,
      );

      final result = classifyDays(
        days: <DateTime>[monday],
        rowTypes: const <DateTime, String>{},
        punchDays: const <DateTime>{},
        holidayDays: const <DateTime>{},
        approvedLeaveDays: const <DateTime>{},
        isWeeklyOff: isDefaultWeeklyOff,
      );

      expect(result.buckets[monday], DayBucket.absent);
      expect(result.absentCount, 1);
      expect(result.countedDays, 1);
    });

    test('"absent" and "a" row types on a working day are absences', () {
      for (final rowType in <String>['absent', 'a', 'unauthorised absent']) {
        expect(
          classifyDay(
            DayInput(day: _march(10), rowType: rowType),
            isWeeklyOff: false,
          ),
          DayBucket.absent,
          reason: 'rowType "$rowType" describes an absence',
        );
      }
    });

    test('an unrecognised row type falls back to an absence', () {
      expect(
        classifyDay(
          DayInput(day: _march(10), rowType: 'not-marked'),
          isWeeklyOff: false,
        ),
        DayBucket.absent,
      );
    });
  });

  group('a day is counted exactly once', () {
    // Risk: the summary page sums the buckets separately. A date present in two
    // buckets inflates the total, so a 31-day month can report 32 days.
    test('a mixed month totals exactly its 31 distinct days', () {
      final holidayMonday = _march(3);
      final leaveTuesday = _march(4);
      final absentsMonday = _march(10);

      final result = classifyDays(
        days: _marchDays(),
        rowTypes: <DateTime, String>{absentsMonday: 'absent'},
        punchDays: <DateTime>{_march(5), _march(6)},
        holidayDays: <DateTime>{holidayMonday},
        approvedLeaveDays: <DateTime>{leaveTuesday},
        isWeeklyOff: isDefaultWeeklyOff,
      );

      expect(result.buckets.length, 31);
      expect(result.presentCount, 2);
      expect(result.holidayCount, 1);
      expect(result.leaveCount, 1);
      expect(result.absentCount, 18); // 22 working days minus 4 explained days.
      expect(result.weeklyOffCount, 9);
      expect(_totalBuckets(result), result.buckets.length);
      expect(
        result.countedDays,
        result.presentCount +
            result.absentCount +
            result.leaveCount +
            result.holidayCount,
      );
      expect(result.countedDays, 22);
    });

    test('a day listed twice is counted once', () {
      final repeated = _march(10);

      final result = classifyDays(
        days: <DateTime>[repeated, repeated, _march(11)],
        rowTypes: const <DateTime, String>{},
        punchDays: const <DateTime>{},
        holidayDays: const <DateTime>{},
        approvedLeaveDays: const <DateTime>{},
        isWeeklyOff: isDefaultWeeklyOff,
      );

      expect(result.buckets.length, 2);
      expect(result.countedDays, 2);
      expect(result.absentCount, 2);
    });

    test('a day in both the punch log and the holiday calendar is counted once',
        () {
      final holidayMonday = _march(3);

      final result = classifyDays(
        days: <DateTime>[holidayMonday],
        rowTypes: const <DateTime, String>{},
        punchDays: <DateTime>{holidayMonday},
        holidayDays: <DateTime>{holidayMonday},
        approvedLeaveDays: <DateTime>{holidayMonday},
        isWeeklyOff: isDefaultWeeklyOff,
      );

      expect(result.buckets.length, 1);
      expect(_totalBuckets(result), 1);
      expect(result.presentCount, 1);
      expect(result.holidayCount, 0);
      expect(result.leaveCount, 0);
    });
  });

  group('calendarDay normalises a timestamp to its date', () {
    // Risk: punches carry a clock time, HRM rows carry a different one and the
    // holiday calendar carries none. Without normalisation the same date keys
    // several entries and only one of them is ever counted.
    test('strips the time component', () {
      final normalised = calendarDay(_marchAt(3, 18, 45));

      expect(normalised, _march(3));
      expect(normalised, DateTime(2025, 3, 3));
      expect(normalised.hour, 0);
      expect(normalised.minute, 0);
      expect(normalised.second, 0);
      expect(normalised.millisecond, 0);
      expect(normalised.microsecond, 0);
    });

    test('leaves a midnight value untouched', () {
      expect(calendarDay(_march(3)), _march(3));
    });

    test('is idempotent', () {
      final once = calendarDay(_marchAt(3, 18, 45));

      expect(calendarDay(once), once);
    });

    test('keys buckets at midnight when inputs carry a clock time', () {
      final result = classifyDays(
        days: <DateTime>[_marchAt(3, 9, 15)],
        rowTypes: const <DateTime, String>{},
        punchDays: <DateTime>{_marchAt(3, 8, 55)},
        holidayDays: const <DateTime>{},
        approvedLeaveDays: const <DateTime>{},
        isWeeklyOff: _noWeeklyOffs,
      );

      expect(result.buckets.length, 1);
      expect(result.buckets.containsKey(_march(3)), isTrue);
      expect(result.buckets[_march(3)], DayBucket.present);
      expect(
        result.buckets.keys.every((key) => key == calendarDay(key)),
        isTrue,
      );
    });

    test('a day listed twice with different times is counted once', () {
      final result = classifyDays(
        days: <DateTime>[_march(10), _marchAt(10, 17, 30)],
        rowTypes: const <DateTime, String>{},
        punchDays: const <DateTime>{},
        holidayDays: const <DateTime>{},
        approvedLeaveDays: const <DateTime>{},
        isWeeklyOff: isDefaultWeeklyOff,
      );

      expect(result.buckets.length, 1);
      expect(result.countedDays, 1);
      expect(result.buckets[_march(10)], DayBucket.absent);
    });
  });
}
