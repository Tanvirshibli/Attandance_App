import 'dart:async';

import 'package:flutter/foundation.dart';

/// What the blocking transaction overlay is doing right now.
enum TransactionStatus { running, success, failure }

/// One transaction's visible state: a progress ring, then a tick or a cross.
@immutable
class TransactionFeedback {
  const TransactionFeedback({
    required this.status,
    this.label = '',
    this.message,
  });

  final TransactionStatus status;

  /// Shown under the ring, e.g. "Checking in".
  final String label;

  /// Shown after a failure, when the caller has something specific to say.
  final String? message;
}

/// Publishes the state of user-initiated backend work to [TransactionOverlay].
///
/// Only actions the user explicitly started belong here: a login, a punch, an
/// enrolment, a preference save, a manual refresh, a logout. Background work
/// (clock resync, geo pings, OTA check, silent token refresh) must stay silent —
/// a barrier that appears while somebody is reading is worse than no feedback.
class TransactionUiService {
  TransactionUiService._();

  static final TransactionUiService instance = TransactionUiService._();

  static const Duration holdAfterOutcome = Duration(seconds: 2);

  final ValueNotifier<TransactionFeedback?> feedback =
      ValueNotifier<TransactionFeedback?>(null);

  Future<void>? _idle;
  Completer<void>? _idleCompleter;
  Timer? _hold;

  bool get isShowing => feedback.value != null;

  /// Runs [action] behind the overlay and returns its value.
  ///
  /// Errors are rethrown unchanged so the caller's existing handling still runs;
  /// the overlay only reflects the outcome. Concurrent callers are queued, so
  /// two quick taps can never stack barriers or dismiss each other's result.
  ///
  /// [isSuccess] exists because several flows here report failure by *returning*
  /// a result object rather than throwing — biometric sign-in among them. Without
  /// a verdict the overlay painted a green tick over a message saying the login
  /// had failed.
  Future<T> run<T>(
    Future<T> Function() action, {
    String label = 'Working',
    String? successMessage,
    bool Function(T value)? isSuccess,
  }) async {
    if (isShowing) await _idleFuture;
    _begin(label);
    try {
      final value = await action();
      if (isSuccess != null && !isSuccess(value)) {
        _finish(TransactionStatus.failure, label, null);
        return value;
      }
      _finish(TransactionStatus.success, label, successMessage);
      return value;
    } catch (_) {
      _finish(TransactionStatus.failure, label, null);
      rethrow;
    }
  }

  /// Runs [action] behind the overlay and reports only success or failure.
  ///
  /// For work whose caller may already be gone — the punch is submitted after
  /// the camera screen pops — so there is nothing to rethrow to.
  Future<bool> runDetached(
    Future<bool> Function() action, {
    String label = 'Working',
    String? successMessage,
    String? failureMessage,
  }) async {
    if (isShowing) await _idleFuture;
    _begin(label);
    bool ok;
    try {
      ok = await action();
    } catch (error) {
      debugPrint('TransactionUiService: $label failed ($error)');
      ok = false;
    }
    _finish(
      ok ? TransactionStatus.success : TransactionStatus.failure,
      label,
      ok ? successMessage : failureMessage,
    );
    return ok;
  }

  /// Clears the overlay immediately. Only the tests and a deliberate reset use
  /// this; normal dismissal is the 2-second timer.
  @visibleForTesting
  void reset() {
    _hold?.cancel();
    _hold = null;
    feedback.value = null;
    _releaseIdle();
  }

  void _begin(String label) {
    _hold?.cancel();
    _hold = null;
    feedback.value = TransactionFeedback(
      status: TransactionStatus.running,
      label: label,
    );
  }

  void _finish(TransactionStatus status, String label, String? message) {
    feedback.value = TransactionFeedback(
      status: status,
      label: label,
      message: message,
    );

    _hold?.cancel();
    _hold = Timer(holdAfterOutcome, () {
      _hold = null;
      feedback.value = null;
      _releaseIdle();
    });
  }

  void _releaseIdle() {
    final completer = _idleCompleter;
    _idleCompleter = null;
    _idle = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  Future<void> get _idleFuture {
    final completer = _idleCompleter ??= Completer<void>();
    return _idle ??= completer.future;
  }
}
