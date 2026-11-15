import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_service.dart';
import 'device_integrity_service.dart';
import 'integrity_api_service.dart';
import 'internet_time_service.dart';

/// Holds the app behind an integrity lock until a password sign-in clears it.
///
/// Why a password and not a button
/// -------------------------------
/// Every violation this service locks on is something the user can simply turn
/// off — the mock-location provider, the fake-GPS app, the edited clock — and
/// then carry on spoofing from a clean state. Requiring the account password
/// makes clearing a lock cost the one thing a person pretending to be at work
/// does not have: the employee's credentials. It also means the lock can never
/// strand somebody, because anyone who can open the app on this phone can also
/// fix it.
///
/// Why the lock survives a restart
/// -------------------------------
/// Without persistence, "locked" means "relaunch the app". The flag, the
/// violation and the moment it was raised go into the platform keystore, and
/// [restore] re-applies them on the next cold start — but only within
/// [restoreWindow] hours, so a phone that sat in a drawer over the weekend does
/// not come back locked for something the employee already fixed.
///
/// Nothing here throws at the caller: [raise] and [restore] are fire-and-forget
/// from the punch path and from `main`.
class IntegrityLockService {
  IntegrityLockService._({IntegrityApiService? api})
      : _api = api ?? IntegrityApiService();

  /// The app-wide instance.
  static final IntegrityLockService instance = IntegrityLockService._();

  static const String _flagKey = 'integrity_lock_active';
  static const String _violationKey = 'integrity_lock_violation';
  static const String _raisedAtKey = 'integrity_lock_raised_at';

  /// A lock older than this is not re-applied on boot. A tampering finding is
  /// about the session it was raised in; keeping it forever would eventually
  /// lock a phone for something that has been fixed for days.
  static const Duration restoreWindow = Duration(hours: 24);

  final IntegrityApiService _api;
  final AuthService _authService = AuthService();

  final FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final ValueNotifier<IntegrityViolation?> _violation =
      ValueNotifier<IntegrityViolation?>(null);

  /// The active lock. `IntegrityGuard` binds to this; the punch path only ever
  /// reads it.
  ValueNotifier<IntegrityViolation?> get violation => _violation;

  /// The violation currently locking the app, if any.
  IntegrityViolation? get current => _violation.value;

  /// Raises the lock: publish, report, persist.
  ///
  /// The notifier is set first and synchronously, so the overlay is already
  /// covering the app by the time the (unawaited) report and the keystore write
  /// finish. Persistence is what survives a restart; it is deliberately not a
  /// precondition for locking.
  Future<void> raise(IntegrityViolation violation) async {
    _violation.value = violation;

    // Telemetry, never awaited behind the lock: a report that cannot be sent
    // must not delay the screen that has to explain what happened.
    unawaited(_api.report(violation));

    try {
      await _secureStorage.write(key: _flagKey, value: '1');
      await _secureStorage.write(
        key: _violationKey,
        value: jsonEncode(violation.toJson()),
      );
      await _secureStorage.write(
        key: _raisedAtKey,
        value: '${DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (error) {
      // The in-process lock still stands; only the restart protection is lost.
      debugPrint('IntegrityLockService: could not persist the lock ($error)');
    }
  }

  /// Clears the lock, but only for a password that actually signs in.
  ///
  /// Returns false on any failure — bad credentials, no network, a timeout — and
  /// leaves the lock exactly as it was. The overlay turns that false into an
  /// inline error rather than dismissing itself.
  Future<bool> unlockWithPassword({
    required String email,
    required String password,
  }) async {
    final AuthResult result;
    try {
      result = await _authService.login(
        email: email,
        password: password,
        // Preserve whatever the phone already remembers: a lock screen is not
        // the place to change someone's "remember me" preference.
        rememberMe: await _authService.getRememberMe(),
      );
    } catch (error) {
      debugPrint('IntegrityLockService: unlock failed ($error)');
      return false;
    }

    if (!result.success) return false;

    _violation.value = null;
    await _clearPersisted();

    // A fresh password session is a fresh integrity window: the next fix must
    // not be judged against the one from before the lock, and a clock-jump
    // finding from the old session must not fire again.
    DeviceIntegrityService.instance.resetForNewSession();

    // The lock may have been about the clock. Re-read internet time now, so the
    // banner the user sees after signing in is about the clock as it is, not as
    // it was when the lock was raised.
    unawaited(InternetTimeService.instance.sync(force: true));

    return true;
  }

  /// Re-applies a persisted lock on boot, if it is recent enough.
  ///
  /// Safe to call before the first frame: it reads the platform keystore only,
  /// never the network. A read failure leaves the app unlocked — the guard's job
  /// is to block tampering, and blocking every punch because a keystore call
  /// threw would be worse than the tampering it is guarding against.
  Future<void> restore() async {
    try {
      final flag = await _secureStorage.read(key: _flagKey);
      if (flag != '1') {
        // No lock was persisted. Clear any half-written leftovers so a stale
        // violation can never be resurrected by a later raise.
        if (flag != null) await _clearPersisted();
        return;
      }

      final raw = await _secureStorage.read(key: _violationKey);
      final raisedAt = int.tryParse(
        (await _secureStorage.read(key: _raisedAtKey)) ?? '',
      );

      if (raw == null || raw.isEmpty) {
        await _clearPersisted();
        return;
      }

      if (raisedAt != null) {
        final ageMs = DateTime.now().millisecondsSinceEpoch - raisedAt;
        // A negative age means the phone's clock moved backwards since the lock
        // was raised. That is itself suspicious, so the lock stands and the
        // password is the way out.
        if (ageMs >= 0 && ageMs > restoreWindow.inMilliseconds) {
          await _clearPersisted();
          return;
        }
      }

      final violation = IntegrityViolation.fromJson(_decode(raw));
      if (violation == null) {
        await _clearPersisted();
        return;
      }

      if (isRetiredFalsePositive(violation)) {
        await _clearPersisted();
        return;
      }

      _violation.value = violation;
    } catch (error) {
      debugPrint('IntegrityLockService: could not restore the lock ($error)');
    }
  }

  /// The email the phone already remembers, for prefilling the lock form.
  ///
  /// Local only, so the sheet opens without waiting on anything.
  Future<String?> savedEmail() async {
    try {
      return await _authService.getSavedEmail();
    } catch (error) {
      debugPrint('IntegrityLockService: no saved email ($error)');
      return null;
    }
  }

  /// Whether a lock is active, in memory or persisted.
  Future<bool> get isLocked async {
    if (_violation.value != null) return true;
    try {
      return await _secureStorage.read(key: _flagKey) == '1';
    } catch (error) {
      debugPrint('IntegrityLockService: could not read the lock ($error)');
      return false;
    }
  }

  /// Drops the in-memory lock without a password.
  ///
  /// Exists for tests and for a deliberate admin reset; nothing in the app calls
  /// it. It does *not* touch the persisted flag, so the next boot is still
  /// protected — use [unlockWithPassword] for the real thing.
  @visibleForTesting
  void clearInMemory() {
    _violation.value = null;
  }

  Future<void> _clearPersisted() async {
    try {
      await _secureStorage.delete(key: _flagKey);
      await _secureStorage.delete(key: _violationKey);
      await _secureStorage.delete(key: _raisedAtKey);
    } catch (error) {
      debugPrint('IntegrityLockService: could not clear the lock ($error)');
    }
  }

  /// A violation type that was found to fire on honest phones and is no longer
  /// produced by any rule. A lock persisted by an older build is dropped on
  /// upgrade instead of re-locking the employee who is stuck behind it.
  static bool isRetiredFalsePositive(IntegrityViolation violation) =>
      violation.type == IntegrityType.mockLocationApp;

  static Object? _decode(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
}
