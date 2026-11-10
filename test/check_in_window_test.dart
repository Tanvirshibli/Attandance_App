import 'package:employee_attendance/utils/check_in_window.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors `pphl_erp/tests/Feature/MobileCheckInWindowTest.php`. Every case
/// passes a fixed `now` so the result never depends on the wall clock.
void main() {
  group('CheckInWindow.evaluate — 09:00 day shift', () {
    final shiftStart = '09:00:00';

    test('is open 14 minutes after the shift start', () {
      final result = CheckInWindow.evaluate(
        shiftStartTime: shiftStart,
        now: DateTime(2025, 3, 10, 9, 14),
      );

      expect(result.isClosed, isFalse);
      expect(result.message, isNull);
      expect(result.deadline, DateTime(2025, 3, 10, 9, 15));
    });

    test('is still open exactly on the deadline (start + 15 min)', () {
      final result = CheckInWindow.evaluate(
        shiftStartTime: shiftStart,
        now: DateTime(2025, 3, 10, 9, 15),
      );

      expect(result.isClosed, isFalse);
      expect(result.message, isNull);
    });

    test('is closed one minute past the deadline', () {
      final result = CheckInWindow.evaluate(
        shiftStartTime: shiftStart,
        now: DateTime(2025, 3, 10, 9, 16),
      );

      expect(result.isClosed, isTrue);
      expect(result.deadline, DateTime(2025, 3, 10, 9, 15));
      expect(result.message, contains('Check-in is closed'));
      expect(result.message, contains('9:00 AM'));
      expect(
        result.message,
        'Check-in is closed. Your shift started at 9:00 AM and the '
        '15-minute grace period has passed.',
      );
    });

    test('is open before the shift starts', () {
      final result = CheckInWindow.evaluate(
        shiftStartTime: shiftStart,
        now: DateTime(2025, 3, 10, 8, 30),
      );

      expect(result.isClosed, isFalse);
      expect(result.deadline, DateTime(2025, 3, 10, 9, 15));
    });
  });

  group('CheckInWindow.evaluate — 23:00 night shift', () {
    final shiftStart = '23:00:00';

    test('is open ten minutes into the shift', () {
      final result = CheckInWindow.evaluate(
        shiftStartTime: shiftStart,
        now: DateTime(2025, 3, 10, 23, 10),
      );

      expect(result.isClosed, isFalse);
      expect(result.deadline, DateTime(2025, 3, 10, 23, 15));
    });

    test('is closed just after midnight, with the deadline rolled back a day',
        () {
      final result = CheckInWindow.evaluate(
        shiftStartTime: shiftStart,
        now: DateTime(2025, 3, 11, 0, 2),
      );

      expect(result.isClosed, isTrue);
      expect(result.deadline, DateTime(2025, 3, 10, 23, 15));
      expect(result.message, contains('11:00 PM'));
    });
  });

  group('CheckInWindow.evaluate — fails open without a usable shift', () {
    final now = DateTime(2025, 3, 10, 23, 30);

    for (final shiftStart in <String?>[
      null,
      '',
      '   ',
      'null',
      'NULL',
      'not-a-time',
      '25:00',
      '09:60',
    ]) {
      test('treats ${shiftStart == null ? 'null' : "'$shiftStart'"} as open',
          () {
        final result = CheckInWindow.evaluate(
          shiftStartTime: shiftStart,
          now: now,
        );

        expect(result.isClosed, isFalse);
        expect(result.deadline, isNull);
        expect(result.message, isNull);
      });
    }
  });

  group('CheckInWindow.evaluate — time formats', () {
    test('parses HH:mm:ss the same as HH:mm', () {
      final now = DateTime(2025, 3, 10, 9, 20);
      final withSeconds = CheckInWindow.evaluate(
        shiftStartTime: '09:00:00',
        now: now,
      );
      final withoutSeconds = CheckInWindow.evaluate(
        shiftStartTime: '09:00',
        now: now,
      );

      expect(withSeconds.isClosed, withoutSeconds.isClosed);
      expect(withSeconds.deadline, withoutSeconds.deadline);
      expect(withSeconds.message, withoutSeconds.message);
    });

    test('tolerates a single-digit hour and surrounding whitespace', () {
      final result = CheckInWindow.evaluate(
        shiftStartTime: ' 9:05 ',
        now: DateTime(2025, 3, 10, 9, 30),
      );

      expect(result.isClosed, isTrue);
      expect(result.message, contains('9:05 AM'));
    });
  });
}
