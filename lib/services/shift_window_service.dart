import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../config/app_config.dart';
import '../utils/check_in_window.dart';
import 'auth_service.dart';
import 'endpoint_config_service.dart';
import 'internet_time_service.dart';

/// Where one side of the shift window stands, as the server reports it.
///
/// `open` and `late` both permit the punch — `late` additionally records that
/// the shift had already started. `before` is too early, `after` is closed, and
/// `no_shift` means HR has no rota for this employee.
enum WindowState { open, before, late, after, noShift }

/// One side (check-in or check-out) of the server's shift window.
class ShiftSideWindow {
  const ShiftSideWindow({
    required this.state,
    this.deadline,
    this.lateMinutes = 0,
    this.graceMinutes = 0,
  });

  final WindowState state;

  /// Last instant the punch is accepted. The server sends either a full
  /// timestamp or a bare `HH:mm[:ss]`; both are normalised to an instant.
  final DateTime? deadline;

  final int lateMinutes;
  final int graceMinutes;

  bool get isAllowed =>
      state == WindowState.open || state == WindowState.late;

  factory ShiftSideWindow.fromJson(
    Object? raw, {
    required DateTime anchor,
    required WindowState fallback,
  }) {
    if (raw is! Map<String, dynamic>) {
      return ShiftSideWindow(state: fallback);
    }

    return ShiftSideWindow(
      state: _stateFrom(raw['state'], fallback),
      deadline: _parseMoment(raw['deadline'], anchor: anchor),
      lateMinutes: _toInt(raw['late_minutes'] ?? raw['lateMinutes']) ?? 0,
      graceMinutes: _toInt(raw['grace_minutes'] ?? raw['graceMinutes']) ?? 0,
    );
  }
}

/// The shift itself, as HRM holds it.
class ShiftInfo {
  const ShiftInfo({
    required this.startTime,
    required this.endTime,
    this.id,
    this.name = '',
    this.sectorId,
  });

  final int? id;
  final String name;
  final String startTime;
  final String endTime;
  final int? sectorId;

  static ShiftInfo? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final start = (raw['start_time'] ?? raw['startTime'] ?? '').toString().trim();
    final end = (raw['end_time'] ?? raw['endTime'] ?? '').toString().trim();
    if (start.isEmpty && end.isEmpty) return null;
    return ShiftInfo(
      id: _toInt(raw['id']),
      name: (raw['name'] ?? '').toString().trim(),
      startTime: start,
      endTime: end,
      sectorId: _toInt(raw['sector_id'] ?? raw['sectorId']),
    );
  }

  /// `09:00 – 20:00`.
  String get label => '${_clockText(startTime)} – ${_clockText(endTime)}';

  /// The shift start anchored to [anchor]'s day, rolled back for a night shift
  /// whose start is still hours away.
  DateTime? startAt(DateTime anchor) =>
      _parseMoment(startTime, anchor: anchor, rollNightShift: true);

  /// The shift end anchored to [anchor]'s day. An end that is not after the
  /// start belongs to the following day (a 23:00–08:00 shift).
  DateTime? endAt(DateTime anchor) {
    final start = startAt(anchor);
    final end = _parseMoment(endTime, anchor: anchor, rollNightShift: false);
    if (start != null && end != null && !end.isAfter(start)) {
      return end.add(const Duration(days: 1));
    }
    return end;
  }
}

/// The payload of `GET /api/v1/mobile/shift-window`.
class ShiftWindow {
  const ShiftWindow({
    required this.fetchedAt,
    required this.inWindow,
    required this.outWindow,
    this.shift,
    this.employeeId,
    this.graceMinutes = 0,
    this.timezone = '',
    this.serverInternetTime,
  });

  /// Best-known moment this payload was received. The window is cached for a
  /// minute, so the deadlines above it can be up to that much out of date.
  final DateTime fetchedAt;

  final ShiftSideWindow inWindow;
  final ShiftSideWindow outWindow;
  final ShiftInfo? shift;
  final int? employeeId;
  final int graceMinutes;
  final String timezone;
  final DateTime? serverInternetTime;

  bool get hasShift => shift != null;

  ShiftSideWindow sideFor({required bool isCheckOut}) =>
      isCheckOut ? outWindow : inWindow;

  static ShiftWindow? fromJson(
    Map<String, dynamic> json, {
    required DateTime fetchedAt,
  }) {
    if (json['success'] == false) return null;

    final shift = ShiftInfo.fromJson(json['shift']);
    final rawWindow = json['window'];
    final windowMap =
        rawWindow is Map<String, dynamic> ? rawWindow : const <String, dynamic>{};
    final fallback = shift == null ? WindowState.noShift : WindowState.open;

    return ShiftWindow(
      fetchedAt: fetchedAt,
      shift: shift,
      employeeId: _toInt(json['employee_id'] ?? json['employeeId']),
      graceMinutes: _toInt(json['grace_minutes'] ?? json['graceMinutes']) ?? 0,
      timezone: (json['timezone'] ?? '').toString(),
      serverInternetTime: _parseMoment(
        json['internet_time'],
        anchor: fetchedAt,
        rollNightShift: false,
      ),
      inWindow: ShiftSideWindow.fromJson(
        windowMap['in'],
        anchor: fetchedAt,
        fallback: fallback,
      ),
      outWindow: ShiftSideWindow.fromJson(
        windowMap['out'],
        anchor: fetchedAt,
        fallback: fallback,
      ),
    );
  }
}

/// The authoritative shift window for the signed-in employee.
///
/// The app used to decide the grace window locally from `shift_start_time` on
/// the device clock, and never gated a check-out at all. The server now owns
/// the window (`GET /api/v1/mobile/shift-window`); this keeps a one-minute copy
/// of it and re-evaluates the state against [InternetTimeService] before every
/// punch, because the cached deadline can be up to a minute behind.
class ShiftWindowService {
  ShiftWindowService._();

  static final ShiftWindowService instance = ShiftWindowService._();

  static const Duration cacheTtl = Duration(seconds: 60);

  final AuthService _authService = AuthService();
  final EndpointConfigService _configService = EndpointConfigService.instance;

  /// Latest successful payload. Null means "never fetched", which callers must
  /// treat as unknown rather than as a closed window.
  final ValueNotifier<ShiftWindow?> window = ValueNotifier<ShiftWindow?>(null);

  final ValueNotifier<bool> loading = ValueNotifier<bool>(false);

  /// Why the last fetch produced nothing usable (surfaced, never blocking).
  String? lastError;

  Future<ShiftWindow?>? _inFlight;

  ShiftWindow? get current => window.value;

  /// Returns the cached window when it is under a minute old, else refetches.
  /// A failed fetch leaves the previous value in place.
  Future<ShiftWindow?> ensure({bool force = false}) {
    final cached = window.value;
    if (!force && cached != null && !_isExpired(cached)) {
      return Future<ShiftWindow?>.value(cached);
    }
    return refresh();
  }

  /// Refetches unconditionally, collapsing concurrent calls into one request.
  Future<ShiftWindow?> refresh() {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    final future = _fetch();
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  /// Re-evaluates the cached window at [at] (pass `InternetTimeService.now()`),
  /// so a deadline the server reported up to a minute ago is still enforced.
  WindowState evaluateLocally(DateTime at, {required bool isCheckOut}) {
    final cached = window.value;
    if (cached == null) return WindowState.noShift;
    final shift = cached.shift;
    if (shift == null) return WindowState.noShift;

    final side = cached.sideFor(isCheckOut: isCheckOut);
    if (side.state == WindowState.noShift) return WindowState.noShift;

    final deadline = deadlineFor(isCheckOut: isCheckOut, at: at);
    if (deadline != null && at.isAfter(deadline)) return WindowState.after;

    final lateMinutes = lateMinutesAt(at, isCheckOut: isCheckOut);
    if (lateMinutes > 0) return WindowState.late;

    if (!isCheckOut) {
      final start = shift.startAt(at);
      if (start != null && at.isBefore(start) && side.state == WindowState.before) {
        return WindowState.before;
      }
    }

    return WindowState.open;
  }

  /// The instant the punch stops being accepted on that side.
  DateTime? deadlineFor({required bool isCheckOut, required DateTime at}) {
    final cached = window.value;
    if (cached == null) return null;

    final side = cached.sideFor(isCheckOut: isCheckOut);
    if (side.deadline != null) return side.deadline;

    final shift = cached.shift;
    if (shift == null) return null;

    if (!isCheckOut) {
      // Same grace period and night-shift rollback the local calculator has
      // always used; only the anchor comes from the server's shift row.
      return CheckInWindow.evaluate(
        shiftStartTime: shift.startTime,
        now: at,
      ).deadline;
    }

    final end = shift.endAt(at);
    if (end == null) return null;
    final grace = side.graceMinutes > 0
        ? side.graceMinutes
        : (cached.graceMinutes > 0
            ? cached.graceMinutes
            : CheckInWindow.graceMinutes);
    return end.add(Duration(minutes: grace));
  }

  /// Lateness in whole minutes against the shift start, using the server's
  /// number when it sent one.
  int lateMinutesAt(DateTime at, {required bool isCheckOut}) {
    final cached = window.value;
    if (cached == null) return 0;

    final side = cached.sideFor(isCheckOut: isCheckOut);
    if (side.lateMinutes > 0) return side.lateMinutes;

    final shift = cached.shift;
    if (shift == null) return 0;

    final anchor = isCheckOut ? shift.endAt(at) : shift.startAt(at);
    if (anchor == null) return 0;
    final minutes = at.difference(anchor).inMinutes;
    return minutes > 0 ? minutes : 0;
  }

  /// A human reason the punch cannot go ahead, or null when it can.
  ///
  /// Check-out always returns null: the officer already punched in, and a closed
  /// window must not trap them on site. Check-in keeps the shift-start tolerance
  /// rule, which is the policy HR relies on.
  ///
  /// Fails open when the window was never fetched: the server still re-checks
  /// every punch, and an unreachable endpoint must not strand the officer.
  String? blockReason({required bool isCheckOut}) {
    // Check-out is never refused on the window: the officer already punched in,
    // and a closed window must not trap them on site. Check-in keeps the
    // shift-start + tolerance rule, which is the actual policy.
    if (isCheckOut) return null;

    final cached = window.value;
    if (cached == null) return null;

    // The window is measured against internet time; without a synced clock the
    // caller has already refused the punch, so only the rota check runs here.
    if (!InternetTimeService.instance.isSynced) {
      if (cached.shift == null && !isCheckOut) {
        return 'No shift assigned to your profile · contact HR to be rostered';
      }
      return null;
    }

    final shift = cached.shift;
    if (shift == null) {
      // A check-out is never blocked on a missing rota: the officer already
      // punched in, and HR removing the shift must not trap them on site.
      if (isCheckOut) return null;
      return 'No shift assigned to your profile · contact HR to be rostered';
    }

    final at = InternetTimeService.instance.now();
    final state = evaluateLocally(at, isCheckOut: isCheckOut);
    final side = isCheckOut ? 'Check-out' : 'Check-in';
    final shiftLabel = shift.label;

    switch (state) {
      case WindowState.after:
        final deadline = deadlineFor(isCheckOut: isCheckOut, at: at);
        final closedAt = deadline == null
            ? '$side window has closed'
            : '$side closed at '
                '${DateFormat('HH:mm').format(deadline.toLocal())}';
        return '$closedAt · shift $shiftLabel · contact HR';
      case WindowState.noShift:
        return 'No shift assigned to your profile · contact HR to be rostered';
      case WindowState.open:
      case WindowState.late:
      case WindowState.before:
        return null;
    }
  }

  /// `Check-in closes in 12m`-style remaining time, or null when unknown.
  String? remainingText({required bool isCheckOut}) {
    final time = InternetTimeService.instance;
    if (!time.isSynced) return null;

    final at = time.now();
    final deadline = deadlineFor(isCheckOut: isCheckOut, at: at);
    if (deadline == null) return null;

    final remaining = deadline.difference(at);
    if (remaining.isNegative) return null;
    if (remaining.inMinutes < 1) return 'under a minute';
    if (remaining.inMinutes < 60) return '${remaining.inMinutes}m';
    return '${remaining.inHours}h ${remaining.inMinutes % 60}m';
  }

  /// Drops the cache so the next [ensure] hits the network.
  void invalidate() {
    window.value = null;
  }

  /// Anchor for the cache timestamps and for bare `HH:mm` server times.
  ///
  /// Internet time when it is available, because that is what the window edges
  /// are measured against. Before the first sync the device clock only decides
  /// how old the cache is — no punch is gated on it.
  DateTime _timeAnchor() {
    final time = InternetTimeService.instance;
    return time.isSynced ? time.now() : DateTime.now();
  }

  bool _isExpired(ShiftWindow cached) {
    final age = _timeAnchor().difference(cached.fetchedAt);
    return age >= cacheTtl;
  }

  Future<ShiftWindow?> _fetch() async {
    loading.value = true;
    try {
      final token = await _authService.getToken();
      if (token == null || token.isEmpty) {
        lastError = 'Please sign in again to load your shift window.';
        return window.value;
      }

      for (final url in await _candidateUrls()) {
        try {
          final response = await http
              .get(
                Uri.parse(url),
                headers: {
                  'Accept': 'application/json',
                  'Authorization': 'Bearer $token',
                  'User-Agent': 'PPHLAttendance/2.3 (Android; Flutter)',
                },
              )
              .timeout(const Duration(seconds: 15));

          if (response.statusCode == 404 || response.statusCode == 405) {
            continue;
          }
          if (response.statusCode != 200) {
            lastError = 'Shift window unavailable (${response.statusCode}).';
            continue;
          }

          final decoded = jsonDecode(response.body);
          if (decoded is! Map<String, dynamic>) continue;

          final parsed = ShiftWindow.fromJson(
            decoded,
            fetchedAt: _timeAnchor(),
          );
          if (parsed == null) {
            lastError = 'This account has no shift window yet.';
            continue;
          }

          lastError = null;
          window.value = parsed;
          return parsed;
        } catch (_) {
          continue;
        }
      }

      return window.value;
    } finally {
      loading.value = false;
    }
  }

  Future<List<String>> _candidateUrls() async {
    final urls = <String>[];

    final configured = await _configService.resolveUrl('shift.window');
    if (configured != null && configured.trim().isNotEmpty) {
      urls.add(configured.trim());
    }

    for (final base in AppConfig.authApiBaseUrlCandidates) {
      final normalized = base.trim().replaceAll(RegExp(r'/+$'), '');
      if (normalized.isEmpty) continue;
      final url = '$normalized/api/v1/mobile/shift-window';
      if (!urls.contains(url)) urls.add(url);
    }

    return urls;
  }
}

/// `09:00:00` -> `09:00`. Anything unrecognised is passed through untouched.
String _clockText(String raw) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(raw.trim());
  if (match == null) return raw.trim();
  final hour = int.tryParse(match.group(1)!) ?? 0;
  return '${hour.toString().padLeft(2, '0')}:${match.group(2)}';
}

WindowState _stateFrom(Object? raw, WindowState fallback) {
  switch ((raw ?? '').toString().trim().toLowerCase()) {
    case 'open':
      return WindowState.open;
    case 'before':
      return WindowState.before;
    case 'late':
      return WindowState.late;
    case 'after':
    case 'closed':
      return WindowState.after;
    case 'no_shift':
    case 'noshift':
    case 'no-shift':
      return WindowState.noShift;
    default:
      return fallback;
  }
}

/// Anchors a bare `HH:mm[:ss]` to [anchor]'s local date; a full timestamp keeps
/// its own date and offset.
DateTime? _parseMoment(
  Object? raw, {
  required DateTime anchor,
  bool rollNightShift = true,
}) {
  final text = (raw ?? '').toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return null;

  final timeOnly = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(text);
  if (timeOnly != null) {
    final hour = int.tryParse(timeOnly.group(1)!);
    final minute = int.tryParse(timeOnly.group(2)!);
    final second = int.tryParse(timeOnly.group(3) ?? '0');
    if (hour == null ||
        minute == null ||
        second == null ||
        hour > 23 ||
        minute > 59 ||
        second > 59) {
      return null;
    }

    var anchored = DateTime(
      anchor.toLocal().year,
      anchor.toLocal().month,
      anchor.toLocal().day,
      hour,
      minute,
      second,
    );
    if (rollNightShift &&
        anchored.difference(anchor) > const Duration(hours: 12)) {
      anchored = anchored.subtract(const Duration(days: 1));
    }
    return anchored;
  }

  return DateTime.tryParse(text);
}

int? _toInt(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString().trim());
}
