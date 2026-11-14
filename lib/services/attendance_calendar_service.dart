import 'package:flutter/foundation.dart';

import '../models/leave_record.dart';
import 'leave_service.dart';

/// Calendar facts a month's attendance cannot be judged without.
///
/// An attendance report may only call a day without punches "absent" if the day
/// is not excused. Weekends it already knows about from app settings, but
/// holidays and approved leave only exist on the server, so they are fetched
/// once for a window and handed around as plain day sets.
///
/// Every day in both sets is a local calendar day normalised to midnight with
/// `DateTime(y, m, d)`, which is the same shape `Set`-membership checks and the
/// report's own `DateTime(year, month, day)` keys use. A timestamp carrying a
/// clock part would silently never match.
class AttendanceCalendar {
  const AttendanceCalendar({
    this.holidays = const {},
    this.approvedLeaveDays = const {},
  });

  /// Every calendar day inside a holiday range returned by the server, clipped
  /// to the requested window.
  final Set<DateTime> holidays;

  /// Every calendar day covered by approved leave, clipped to the requested
  /// window.
  final Set<DateTime> approvedLeaveDays;

  /// True when neither set holds a day — either the window genuinely has no
  /// holiday or leave, or both sources were unreachable. The two cases are
  /// deliberately not distinguished here: paranoia about a missing punch is the
  /// caller's policy, and it should stay conservative rather than guess.
  bool get isEmpty => holidays.isEmpty && approvedLeaveDays.isEmpty;
}

/// One source's contribution to a [AttendanceCalendar].
///
/// The `answered` flag travels beside the (possibly empty) day set because
/// "this month has no holidays" and "the server did not tell us" must not be
/// confused when deciding whether the combined result is worth caching.
typedef _SourceDays = ({Set<DateTime> days, bool answered});

/// One cached calendar plus the wall-clock stamp its TTL is measured from.
class _CacheEntry {
  const _CacheEntry({required this.calendar, required this.storedAt});

  final AttendanceCalendar calendar;
  final DateTime storedAt;
}

/// Loads holidays and the employee's approved leave as sets of calendar days.
///
/// This is a wrapper, not an owner: [LeaveService] still speaks the HTTP API,
/// while this class answers the one question the attendance report asks —
/// "which days in this window are excused?" — and absorbs every way that
/// question can fail.
class AttendanceCalendarService {
  /// A public constructor with an injectable [LeaveService] rather than the
  /// private constructor the other singletons here use: tests drive [load] with
  /// canned holiday and leave responses, and [instance] is only the production
  /// wiring of that same seam.
  AttendanceCalendarService({LeaveService? leaveService})
    : _leaveService = leaveService ?? LeaveService();

  static final AttendanceCalendarService instance = AttendanceCalendarService();

  /// Holiday edits and leave approvals are rare compared with how often a
  /// report is reopened (tab switches, pull-to-refresh, moving between months),
  /// so a short TTL removes most round-trips. Five minutes is also short enough
  /// that a leave approved while the user is in the app shows up by the time
  /// they look twice, which matters because the cache has no invalidation hook
  /// into the approval flow.
  static const Duration _cacheTtl = Duration(minutes: 5);

  final LeaveService _leaveService;

  /// Keyed `'<employeeId>|<from>|<to>'` with ISO dates, so the same window for
  /// the same employee is a hit and any other window is not.
  final Map<String, _CacheEntry> _cache = <String, _CacheEntry>{};

  /// Holidays and approved leave for `from..to`, both inclusive.
  ///
  /// Never throws. The caller is a stats screen whose calendar it decorates; a
  /// server that cannot describe its holidays must degrade to "no exceptions
  /// known", never to a red error box over a report the user can otherwise read.
  /// Each source fails independently, so an unreachable holiday endpoint still
  /// leaves approved leave — and vice versa — intact.
  Future<AttendanceCalendar> load({
    required int employeeId,
    required DateTime from,
    required DateTime to,
  }) async {
    final start = _day(from);
    final end = _day(to);
    final fromYmd = _iso(start);
    final toYmd = _iso(end);
    final cacheKey = '$employeeId|$fromYmd|$toYmd';

    final cached = _cache[cacheKey];
    if (cached != null) {
      if (DateTime.now().difference(cached.storedAt) <= _cacheTtl) {
        return cached.calendar;
      }
      // Drop stale entries as they are met, so paging through months for hours
      // cannot grow the map without bound.
      _cache.remove(cacheKey);
    }

    try {
      // Concurrent because the two endpoints share nothing and the report is
      // blocked on both: run in sequence, the window takes twice as long to
      // decorate.
      final sources = await Future.wait(<Future<_SourceDays>>[
        _loadHolidays(fromYmd: fromYmd, toYmd: toYmd, from: start, to: end),
        if (employeeId > 0)
          _loadApprovedLeave(employeeId: employeeId, from: start, to: end)
        else
          // There is nobody to ask about: skipping the call avoids sending
          // `employeeId=0` and inviting the server to answer for someone else.
          Future<_SourceDays>.value((
            days: const <DateTime>{},
            answered: false,
          )),
      ]);

      final calendar = AttendanceCalendar(
        holidays: sources[0].days,
        approvedLeaveDays: sources[1].days,
      );

      // A result where neither source answered is an outage, not an answer.
      // Caching it would pin an empty calendar for the whole TTL, so the next
      // call is allowed to retry immediately instead.
      if (sources[0].answered || sources[1].answered) {
        _cache[cacheKey] = _CacheEntry(
          calendar: calendar,
          storedAt: DateTime.now(),
        );
      }
      return calendar;
    } catch (error) {
      // Belt and braces: both loaders swallow their own failures, but an
      // injected or refactored source must not be able to take the report down.
      debugPrint('AttendanceCalendarService.load failed: $error');
      return const AttendanceCalendar();
    }
  }

  /// Forgets every cached window.
  ///
  /// For callers that know the answer changed ahead of the TTL — an employee
  /// switch, or a leave just applied for — since nothing else can reach in here.
  void clearCache() => _cache.clear();

  Future<_SourceDays> _loadHolidays({
    required String fromYmd,
    required String toYmd,
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final result = await _leaveService.getHolidays(from: fromYmd, to: toYmd);

      if (!result.success) {
        debugPrint(
          'AttendanceCalendarService: holidays unavailable — ${result.message}',
        );
        return (days: const <DateTime>{}, answered: false);
      }

      final days = <DateTime>{};
      for (final row in result.data ?? const <Map<String, dynamic>>[]) {
        final span = _holidaySpan(row);
        // A row whose dates do not parse is dropped silently: one malformed
        // holiday is not worth losing the others over.
        if (span == null) continue;
        days.addAll(
          _expandInclusive(
            start: span.start,
            end: span.end,
            from: from,
            to: to,
          ),
        );
      }
      return (days: days, answered: true);
    } catch (error) {
      debugPrint('AttendanceCalendarService: holiday load threw $error');
      return (days: const <DateTime>{}, answered: false);
    }
  }

  Future<_SourceDays> _loadApprovedLeave({
    required int employeeId,
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final result = await _leaveService.getLeaveHistory(
        employeeId: employeeId,
        status: 'approved',
      );

      if (!result.success) {
        debugPrint(
          'AttendanceCalendarService: leave history unavailable — '
          '${result.message}',
        );
        return (days: const <DateTime>{}, answered: false);
      }

      final days = <DateTime>{};
      for (final record in result.data ?? const <LeaveRecord>[]) {
        // The status is a query parameter, so a server that ignores it would
        // let a pending or rejected request excuse a missing punch. Re-check
        // every record here; the compare is trimmed and lowercased because the
        // API has been seen returning 'Approved' and ' approved'.
        if (record.status.trim().toLowerCase() != 'approved') continue;

        final start = _parseDay(record.startDate);
        if (start == null) continue;
        final parsedEnd = _parseDay(record.endDate);
        // A missing or inverted end means a single-day leave, which is a fact
        // worth keeping rather than an error worth discarding.
        final end = (parsedEnd == null || parsedEnd.isBefore(start))
            ? start
            : parsedEnd;

        days.addAll(
          _expandInclusive(start: start, end: end, from: from, to: to),
        );
      }
      return (days: days, answered: true);
    } catch (error) {
      debugPrint('AttendanceCalendarService: leave load threw $error');
      return (days: const <DateTime>{}, answered: false);
    }
  }

  /// The day range one holiday row covers, or `null` when nothing in it parses.
  ///
  /// The mobile holiday endpoint speaks `holidayName` / `startDate` / `endDate`,
  /// but single-day rows have also arrived as `date` and, from the older
  /// web-derived data, `holidayDate`. Accepting them in that order marks the day
  /// whichever shape turns up, instead of dropping holidays without a cue.
  static ({DateTime start, DateTime end})? _holidaySpan(
    Map<String, dynamic> row,
  ) {
    final start =
        _parseDay(row['startDate']) ??
        _parseDay(row['date']) ??
        _parseDay(row['holidayDate']);
    if (start == null) return null;

    final end =
        _parseDay(row['endDate']) ??
        _parseDay(row['date']) ??
        _parseDay(row['holidayDate']) ??
        start;

    return (start: start, end: end.isBefore(start) ? start : end);
  }

  /// Parses a server date into a normalised calendar day, or `null`.
  ///
  /// `DateTime.tryParse` keeps any time-of-day a timestamp carries, which would
  /// break [Set] equality against days built elsewhere in the app, so the clock
  /// part is stripped here rather than at every call site.
  static DateTime? _parseDay(Object? raw) {
    if (raw == null) return null;
    final text = raw.toString().trim();
    if (text.isEmpty) return null;
    final parsed = DateTime.tryParse(text);
    return parsed == null ? null : _day(parsed);
  }

  /// Every day in `start..end`, both inclusive, clipped to `from..to`.
  ///
  /// Clipping before looping bounds the work by the window the caller asked
  /// for, so a holiday row carrying a wildly wrong end date cannot spin here,
  /// and callers get a set they can use as-is.
  static Set<DateTime> _expandInclusive({
    required DateTime start,
    required DateTime end,
    required DateTime from,
    required DateTime to,
  }) {
    final first = start.isAfter(from) ? start : from;
    final last = end.isBefore(to) ? end : to;
    if (last.isBefore(first)) return const <DateTime>{};

    final days = <DateTime>{};
    var cursor = first;
    while (!cursor.isAfter(last)) {
      days.add(cursor);
      // Step by calendar day, not by a 24-hour Duration: the latter drifts
      // across a daylight-saving change and would skip or repeat a date.
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
    }
    return days;
  }

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// `yyyy-MM-dd`, which is what the holidays endpoint filters on (it drops the
  /// range entirely when either bound is missing) and what the cache key is
  /// built from.
  static String _iso(DateTime day) {
    final month = day.month.toString().padLeft(2, '0');
    final dayOfMonth = day.day.toString().padLeft(2, '0');
    return '${day.year.toString().padLeft(4, '0')}-$month-$dayOfMonth';
  }
}
