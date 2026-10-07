import 'package:employee_attendance/models/sales_booking_post_models.dart';
import 'package:employee_attendance/services/sales_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// `POST /api/booking-person-books` stores a **Sales** id in its
/// `bookingPerson` field — `users.id` for feed, `sales_employees_flat.id` for
/// chicks. An officer with no sales account cannot resolve one, so the request
/// always carries the HRM employee id as `bookingPersonEmployeeId` and the
/// backend resolves the Sales id from it. A booking must never depend on the
/// officer having a sales account.
///
/// These tests pin the lookup-endpoint parsing and the payload the app sends in
/// each case.
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

    test('returns null for an empty list (no sales account)', () {
      expect(SalesService.salesUserIdFromList('{"data":[]}'), isNull);
    });

    test('returns null on junk rather than throwing', () {
      expect(SalesService.salesUserIdFromList('not json'), isNull);
    });
  });

  group('CreateBookingPersonBookRequest — the booking payload', () {
    CreateBookingPersonBookRequest request({
      int? bookingPerson,
      int? bookingPersonEmployeeId,
    }) {
      return CreateBookingPersonBookRequest(
        module: 'feed',
        dealerId: 7,
        categoryId: 1,
        subCategoryId: 2,
        childCategoryId: 3,
        bookingPointId: 4,
        bookingPerson: bookingPerson,
        bookingPersonEmployeeId: bookingPersonEmployeeId,
        bookingType: 'Sale',
        isBookingMoney: false,
        isMultiDelivery: false,
        discount: 0,
        discountType: 'Discount',
        advanceAmount: 0,
        totalAmount: 100,
        bookingDate: '2026-10-07',
        invoiceDate: '2026-10-07',
        lines: const [
          BookingLineInput(productId: 11, unitId: 1, qty: 5, price: 20),
        ],
      );
    }

    test('no sales account: sends the HRM employee id, omits bookingPerson',
        () {
      final fields = request(bookingPersonEmployeeId: 19).toFormFields();
      expect(fields['bookingPersonEmployeeId'], '19');
      expect(fields.containsKey('bookingPerson'), isFalse);
    });

    test('sales account linked: sends both ids', () {
      final fields =
          request(bookingPerson: 14, bookingPersonEmployeeId: 19)
              .toFormFields();
      expect(fields['bookingPerson'], '14');
      expect(fields['bookingPersonEmployeeId'], '19');
    });

    test('no ids at all: neither key is sent — the booking still posts', () {
      final fields = request().toFormFields();
      expect(fields.containsKey('bookingPerson'), isFalse);
      expect(fields.containsKey('bookingPersonEmployeeId'), isFalse);
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
