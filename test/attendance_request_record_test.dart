import 'package:employee_attendance/models/attendance_request_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AttendanceRequestRecord calendar day', () {
    test('matches today when attDate is yesterday but in-time is today', () {
      final today = DateTime(2026, 8, 11);
      const record = AttendanceRequestRecord(
        id: 1,
        attDate: '2026-08-10',
        requestType: 'zkteco_daily_span',
        status: 'requested',
        requestedInTime: '2026-08-11 08:43:00',
      );

      expect(record.matchesCalendarDay(today), isTrue);
      expect(record.effectiveCalendarDay, DateTime(2026, 8, 11));
    });

    test('matches today from attDate when no punch timestamps', () {
      final today = DateTime(2026, 8, 11);
      const record = AttendanceRequestRecord(
        id: 2,
        attDate: '2026-08-11',
        requestType: 'self_punch',
        status: 'requested',
      );

      expect(record.matchesCalendarDay(today), isTrue);
      expect(record.effectiveCalendarDay, DateTime(2026, 8, 11));
    });

    test('does not match today when all dates are on another day', () {
      final today = DateTime(2026, 8, 11);
      const record = AttendanceRequestRecord(
        id: 3,
        attDate: '2026-08-09',
        requestType: 'self_punch',
        status: 'requested',
        requestedInTime: '2026-08-09 09:00:00',
      );

      expect(record.matchesCalendarDay(today), isFalse);
    });
  });

  group('AttendanceRequestRecord day-complete punch state', () {
    test('pending in+out allows update checkout but not day complete', () {
      const record = AttendanceRequestRecord(
        id: 4,
        attDate: '2026-08-11',
        requestType: 'self_punch',
        status: 'requested',
        requestedInTime: '2026-08-11 10:28:00',
        requestedOutTime: '2026-08-11 13:42:00',
      );

      expect(record.isDayComplete, isFalse);
      expect(record.canUpdateCheckOut, isTrue);
      expect(record.canPunchCheckIn, isFalse);
      expect(record.canPunchCheckOut, isTrue);
    });

    test('approved in+out is day complete', () {
      const record = AttendanceRequestRecord(
        id: 8,
        attDate: '2026-08-11',
        requestType: 'self_punch',
        status: 'approved',
        requestedInTime: '2026-08-11 10:28:00',
        requestedOutTime: '2026-08-11 13:42:00',
      );

      expect(record.isDayComplete, isTrue);
      expect(record.canPunchCheckOut, isFalse);
    });

    test('canPunchCheckOut when checked in only', () {
      const record = AttendanceRequestRecord(
        id: 5,
        attDate: '2026-08-11',
        requestType: 'self_punch',
        status: 'requested',
        requestedInTime: '2026-08-11 10:28:00',
      );

      expect(record.isDayComplete, isFalse);
      expect(record.canPunchCheckIn, isFalse);
      expect(record.canPunchCheckOut, isTrue);
      expect(record.canTreatAsActiveCheckIn, isTrue);
    });

    test('canPunchCheckIn when no punches yet', () {
      const record = AttendanceRequestRecord(
        id: 6,
        attDate: '2026-08-11',
        requestType: 'self_punch',
        status: 'requested',
      );

      expect(record.isDayComplete, isFalse);
      expect(record.canPunchCheckIn, isTrue);
      expect(record.canPunchCheckOut, isFalse);
    });

    test('rejected record cannot punch or complete day', () {
      const record = AttendanceRequestRecord(
        id: 7,
        attDate: '2026-08-11',
        requestType: 'self_punch',
        status: 'rejected',
        requestedInTime: '2026-08-11 10:28:00',
        requestedOutTime: '2026-08-11 13:42:00',
      );

      expect(record.isDayComplete, isFalse);
      expect(record.canPunchCheckIn, isFalse);
      expect(record.canPunchCheckOut, isFalse);
    });
  });

  group('AttendanceRequestRecord workedHoursOnDay', () {
    test('rebases cross-day in/out onto the target day (not 27.6h)', () {
      const record = AttendanceRequestRecord(
        id: 9,
        attDate: '2026-08-15',
        requestType: 'self_punch',
        status: 'requested',
        requestedInTime: '2026-08-14 10:43:00',
        requestedOutTime: '2026-08-15 14:21:00',
      );

      final hours = record.workedHoursOnDay(DateTime(2026, 8, 15));
      expect(hours, isNotNull);
      expect(hours!.toStringAsFixed(1), '3.6');
    });

    test('same-day 10:43 to 14:21 is 3.6h', () {
      const record = AttendanceRequestRecord(
        id: 10,
        attDate: '2026-08-15',
        requestType: 'self_punch',
        status: 'requested',
        requestedInTime: '2026-08-15 10:43:00',
        requestedOutTime: '2026-08-15 14:21:00',
      );

      final hours = record.workedHoursOnDay(DateTime(2026, 8, 15));
      expect(hours, isNotNull);
      expect(hours!.toStringAsFixed(1), '3.6');
    });
  });
}
