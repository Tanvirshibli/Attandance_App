import 'package:employee_attendance/models/attendance_request_record.dart';
import 'package:employee_attendance/services/attendance_request_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = AttendanceRequestService();

  group('AttendanceRequestService today merge', () {
    test('mergeRecords combines in-only and out-only rows for same day', () {
      const inOnly = AttendanceRequestRecord(
        id: 10,
        attDate: '2026-08-10',
        requestType: 'zkteco_daily_span',
        status: 'requested',
        requestedInTime: '2026-08-11 08:43:00',
        deviceType: 'zkteco',
      );
      const outOnly = AttendanceRequestRecord(
        id: 11,
        attDate: '2026-08-11',
        requestType: 'self_punch',
        status: 'requested',
        requestedOutTime: '2026-08-11 18:00:00',
        deviceType: 'android',
      );

      final merged = service.mergeRecords([inOnly, outOnly]);

      expect(merged.hasCheckIn, isTrue);
      expect(merged.hasCheckOut, isTrue);
      expect(merged.requestedInTime, '2026-08-11 08:43:00');
      expect(merged.requestedOutTime, '2026-08-11 18:00:00');
      expect(merged.deviceType, 'mixed');
    });

    test('resolveTodayRecord merges split rows for today', () {
      final today = DateTime(2026, 8, 11);
      const records = [
        AttendanceRequestRecord(
          id: 10,
          attDate: '2026-08-10',
          requestType: 'zkteco_daily_span',
          status: 'requested',
          requestedInTime: '2026-08-11 08:43:00',
        ),
        AttendanceRequestRecord(
          id: 11,
          attDate: '2026-08-11',
          requestType: 'self_punch',
          status: 'requested',
          requestedOutTime: '2026-08-11 18:00:00',
        ),
      ];

      final todayRecord = service.resolveTodayRecord(records, today);

      expect(todayRecord, isNotNull);
      expect(todayRecord!.hasCheckIn, isTrue);
      expect(todayRecord.hasCheckOut, isTrue);
      expect(todayRecord.isDayComplete, isFalse);
      expect(todayRecord.canPunchCheckOut, isTrue);
    });

    test('mergeRecords prefers approved status over requested', () {
      const requested = AttendanceRequestRecord(
        id: 30,
        attDate: '2026-08-11',
        requestType: 'self_punch',
        status: 'requested',
        requestedInTime: '2026-08-11 09:00:00',
      );
      const approved = AttendanceRequestRecord(
        id: 31,
        attDate: '2026-08-11',
        requestType: 'self_punch',
        status: 'approved',
        requestedOutTime: '2026-08-11 18:00:00',
      );

      final merged = service.mergeRecords([requested, approved]);

      expect(merged.status, 'approved');
      expect(merged.isDayComplete, isTrue);
    });

    test('mergeRecords preserves check-in when API row is out-only', () {
      const local = AttendanceRequestRecord(
        id: 20,
        attDate: '2026-08-11',
        requestType: 'self_punch',
        status: 'requested',
        requestedInTime: '2026-08-11 09:05:00',
      );
      const apiOutOnly = AttendanceRequestRecord(
        id: 21,
        attDate: '2026-08-11',
        requestType: 'self_punch',
        status: 'requested',
        requestedOutTime: '2026-08-11 18:00:00',
      );

      final merged = service.mergeRecords([local, apiOutOnly]);

      expect(merged.hasCheckIn, isTrue);
      expect(merged.hasCheckOut, isTrue);
      expect(merged.canPunchCheckOut, isTrue);
    });

    test('synthesizePunchRecord builds checkout row without request wrapper', () {
      final record = service.synthesizePunchRecord(
        postBody: {
          'attDate': '2026-08-11',
          'requestedOutTime': '2026-08-11 16:00:00',
          'requestType': 'self_punch',
        },
        isCheckOut: true,
      );

      expect(record.hasCheckOut, isTrue);
      expect(record.requestedOutTime, '2026-08-11 16:00:00');
      expect(record.status, 'requested');
    });

    test('in-only record enables checkout', () {
      const apiInOnly = AttendanceRequestRecord(
        id: 40,
        attDate: '2026-08-11',
        requestType: 'self_punch',
        status: 'requested',
        requestedInTime: '2026-08-11 10:28:00',
      );

      expect(apiInOnly.hasCheckOut, isFalse);
      expect(apiInOnly.canPunchCheckOut, isTrue);
      expect(apiInOnly.isDayComplete, isFalse);
    });
  });
}
