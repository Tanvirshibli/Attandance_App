import 'package:flutter/foundation.dart';

/// Signals that a punch's background submission finished.
///
/// The check-in screen now hands control back to the dashboard the instant the
/// face verifies and finishes the submission on its own. This lets the dashboard
/// re-sync once that lands — and surface a failure, so a punch that never
/// reached the server is not silently left looking done.
class AttendancePunchNotifier {
  AttendancePunchNotifier._();

  /// Bumped once per completed background submission.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Direction of the most recent submission, so the dashboard waits for the
  /// right kind of record.
  static bool lastWasCheckOut = false;

  /// Whether the most recent submission reached the server.
  static bool lastSucceeded = true;

  /// Server's reason when it did not.
  static String? lastFailureMessage;

  static void notifySubmitted({
    required bool isCheckOut,
    required bool succeeded,
    String? message,
  }) {
    lastWasCheckOut = isCheckOut;
    lastSucceeded = succeeded;
    lastFailureMessage = message;
    revision.value++;
  }
}
