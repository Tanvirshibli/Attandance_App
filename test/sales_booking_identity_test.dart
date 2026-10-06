import 'package:employee_attendance/services/sales_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// `POST /api/booking-person-books` validates `bookingPerson` against a *Sales*
/// id — `users.id` for feed, `sales_employees_flat.id` for chicks — and rejects
/// the HRM employee id the app used to send with a bare
/// `{"message":"Validation failed."}`.
///
/// These tests pin the parsing of the two endpoints used to resolve the right
/// id, and the surfacing of the field error instead of the generic message.
void main() {
  group('salesUserIdFromList — GET /api/v2/user/list', () {
    test('reads data[].id, which is users.id', () {
      const body = '{"message":"Success!","data":[{"id":14,"employeeId":19}]}';
      expect(SalesService.salesUserIdFromList(body), 14);
    });

    test('skips entries without a usable id', () {
      const body = '{"data":[{"employeeId":19},{"id":14}]}';
      expect(SalesService.salesUserIdFromList(body), 14);
    });

    test('returns null for an empty list (account not linked)', () {
      expect(SalesService.salesUserIdFromList('{"data":[]}'), isNull);
    });

    test('returns null on junk rather than throwing', () {
      expect(SalesService.salesUserIdFromList('not json'), isNull);
    });
  });

  group('salesUserIdFromMe — GET /api/v2/get-my-info', () {
    test('reads user.id', () {
      expect(
        SalesService.salesUserIdFromMe('{"message":"ok","user":{"id":14}}'),
        14,
      );
    });

    test('returns null when the payload has no user', () {
      expect(SalesService.salesUserIdFromMe('{"message":"ok"}'), isNull);
    });
  });

  group('submitErrorMessage — the toast text', () {
    test('prefers the field error over the generic message', () {
      const body = '{"success":false,"message":"Validation failed.",'
          '"errors":{"bookingPerson":["Booking person is required."]}}';
      expect(
        SalesService.submitErrorMessage(body),
        'Booking person is required.',
      );
    });

    test('falls back to message when there are no errors', () {
      expect(
        SalesService.submitErrorMessage('{"message":"Booking created."}'),
        'Booking created.',
      );
    });

    test('returns null when there is nothing usable', () {
      expect(SalesService.submitErrorMessage('nope'), isNull);
    });
  });
}
