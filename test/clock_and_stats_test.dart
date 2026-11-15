import 'package:employee_attendance/models/attendance_classifier.dart';
import 'package:employee_attendance/services/attendance_stats_service.dart';
import 'package:employee_attendance/widgets/attendance_clock_card.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime day(int year, int month, int dayOfMonth) =>
    DateTime(year, month, dayOfMonth);

void main() {
  group('clock formatting', () {
    test('renders AM for the morning', () {
      final time = DateTime(2026, 11, 15, 9, 5);

      expect(formatClock(time), '09:05');
      expect(formatMeridiem(time), 'AM');
    });

    test('renders PM for the afternoon and midnight correctly', () {
      final afternoon = DateTime(2026, 11, 15, 13, 34);
      final midnight = DateTime(2026, 11, 15, 0, 7);

      expect(formatClock(afternoon), '01:34');
      expect(formatMeridiem(afternoon), 'PM');
      expect(formatClock(midnight), '12:07');
      expect(formatMeridiem(midnight), 'AM');
    });
  });

  group('stats without an open today', () {
    test('drops an unevidenced today from the absence count', () {
      final today = day(2026, 11, 15);
      final classification = AttendanceClassification(<DateTime, DayBucket>{
        day(2026, 11, 13): DayBucket.present,
        day(2026, 11, 14): DayBucket.holiday,
        today: DayBucket.absent,
      });

      final result = AttendanceStatsService.withoutOpenTodayAbsence(
        classification,
        today: today,
      );

      expect(result.absentCount, 0);
      expect(result.presentCount, 1);
      expect(result.holidayCount, 1);
      expect(result.buckets.containsKey(today), isFalse);
    });

    test('keeps today when it was punched', () {
      final today = day(2026, 11, 15);
      final classification = AttendanceClassification(<DateTime, DayBucket>{
        today: DayBucket.present,
      });

      final result = AttendanceStatsService.withoutOpenTodayAbsence(
        classification,
        today: today,
      );

      expect(result.presentCount, 1);
    });
  });
}
