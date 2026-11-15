import 'dart:async';

import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../services/internet_time_service.dart';
import '../services/location_gate_service.dart';
import '../services/shift_window_service.dart';
import 'syncing_time.dart';
import 'ui/ui.dart' as ui;

/// Reports which window the tapped button was drawn for, so the caller can
/// refuse a punch the card already knew was closed without another round trip.
typedef PunchWindowCallback = void Function(WindowState? state);

/// The dashboard's single attendance card: network clock, shift window and the
/// two punch buttons.
///
/// It replaces the old header time block and the separate action card, which
/// disagreed with each other — the block showed a time off the device clock
/// while the action card judged the window from a different copy of the shift.
/// The ticking is local to this widget: the dashboard is not rebuilt every
/// second.
class AttendanceClockCard extends StatefulWidget {
  const AttendanceClockCard({
    super.key,
    required this.canCheckIn,
    required this.canCheckOut,
    required this.isDayComplete,
    required this.checkInTime,
    required this.checkOutTime,
    required this.syncingCheckIn,
    required this.syncingCheckOut,
    required this.faceRegistered,
    required this.fingerprintEnrolled,
    required this.busy,
    required this.onCheckIn,
    required this.onCheckOut,
  });

  final bool canCheckIn;
  final bool canCheckOut;
  final bool isDayComplete;
  final String checkInTime;
  final String checkOutTime;
  final bool syncingCheckIn;
  final bool syncingCheckOut;

  /// Needed for the per-button reason: a punch that this device cannot
  /// authorise is disabled before the camera ever opens.
  final bool faceRegistered;
  final bool fingerprintEnrolled;

  /// A punch (or the check flow) is already in flight.
  final bool busy;

  final PunchWindowCallback onCheckIn;
  final PunchWindowCallback onCheckOut;

  @override
  State<AttendanceClockCard> createState() => _AttendanceClockCardState();
}

class _AttendanceClockCardState extends State<AttendanceClockCard>
    with SingleTickerProviderStateMixin {
  /// Past this age the offset is no longer worth stamping a punch with.
  static const Duration _staleAfter = Duration(minutes: 5);

  static const Duration _windowPoll = Duration(seconds: 60);

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  late final Animation<double> _pulse = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1,
        end: 1.035,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.035,
        end: 1,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 60,
    ),
  ]).animate(_pulseController);

  Timer? _ticker;
  Timer? _poller;

  /// Internet time in UTC; null until the service has a verified anchor.
  DateTime? _nowUtc;

  String? _gpsReason;

  @override
  void initState() {
    super.initState();
    _nowUtc = _readInternetTime();
    // 250ms polling keeps the seconds digit from skipping under a loaded frame;
    // setState only runs when a visible digit actually changes.
    _ticker = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _tick(),
    );
    _poller = Timer.periodic(_windowPoll, (_) => _poll());
    unawaited(_refreshWindow());
    unawaited(_refreshLocationGate());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _poller?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  /// Internet time, or null while the clock is unverified.
  ///
  /// The service throws rather than hand back a device-stamped time, so every
  /// read goes through here.
  DateTime? _readInternetTime() {
    final time = InternetTimeService.instance;
    return time.isSynced ? time.now() : null;
  }

  /// Internet time in the device's timezone, for display.
  DateTime? get _localNow => _nowUtc?.toLocal();

  void _tick() {
    if (!mounted) return;
    final now = _readInternetTime();
    final previous = _nowUtc;

    if (now == null) {
      if (previous != null) setState(() => _nowUtc = null);
      return;
    }

    if (previous != null &&
        now.second == previous.second &&
        now.minute == previous.minute &&
        now.hour == previous.hour) {
      return;
    }

    final minuteRolled =
        previous == null || now.minute != previous.minute || now.hour != previous.hour;
    setState(() => _nowUtc = now);
    if (minuteRolled) _pulseController.forward(from: 0);
  }

  void _poll() {
    unawaited(_refreshWindow());
    unawaited(_refreshLocationGate());
  }

  /// The cached window is a minute old at most; `ensure` is a no-op inside that.
  Future<void> _refreshWindow({bool force = false}) async {
    try {
      await ShiftWindowService.instance.ensure(force: force);
    } catch (_) {
      // The card keeps rendering the last known window.
    }
  }

  Future<void> _refreshLocationGate() async {
    String? reason;
    try {
      final gate = await const LocationGateService().check();
      if (gate.isBlocking) reason = gate.reason;
    } catch (_) {
      reason = null;
    }
    if (!mounted || reason == _gpsReason) return;
    setState(() => _gpsReason = reason);
  }

  @override
  Widget build(BuildContext context) {
    return FadeInUp(
      delay: const Duration(milliseconds: 300),
      duration: const Duration(milliseconds: 500),
      child: Container(
        padding: const EdgeInsets.all(ui.AppSpace.md + 2),
        decoration: BoxDecoration(
          gradient: ui.AppColors.brandGradient,
          borderRadius: BorderRadius.circular(ui.AppRadius.xxl),
          boxShadow: ui.AppShadows.raised,
        ),
        child: ValueListenableBuilder<ShiftWindow?>(
          valueListenable: ShiftWindowService.instance.window,
          builder: (context, window, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopRow(window),
              const SizedBox(height: ui.AppSpace.sm),
              _buildClock(),
              const SizedBox(height: ui.AppSpace.xs),
              Center(child: _buildTimeBadge()),
              const SizedBox(height: ui.AppSpace.md),
              _buildWindowRow(window),
              const SizedBox(height: ui.AppSpace.md),
              Divider(color: Colors.white.withValues(alpha: 0.18), height: 1),
              const SizedBox(height: ui.AppSpace.md),
              _buildPunchRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopRow(ShiftWindow? window) {
    final now = _localNow;
    final shift = window?.shift;
    final shiftName = shift == null
        ? 'No shift assigned'
        : (shift.name.isEmpty ? 'Shift' : shift.name);

    return Row(
      children: [
        Expanded(
          child: Text(
            now == null ? 'Date unavailable' : DateFormat('EEE, d MMM').format(now),
            style: ui.AppType.bodyStrong.copyWith(color: Colors.white),
          ),
        ),
        Text(
          shiftName,
          style: ui.AppType.meta.copyWith(color: Colors.white70),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildClock() {
    const figures = [FontFeature.tabularFigures()];
    final now = _localNow;
    final hours = now == null ? '--:--' : DateFormat('HH:mm').format(now);
    final seconds = now == null ? '--' : DateFormat('ss').format(now);

    return Center(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) =>
            Transform.scale(scale: _pulse.value, child: child),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              hours,
              style: GoogleFonts.poppins(
                fontSize: 44,
                height: 1.05,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                fontFeatures: figures,
              ),
            ),
            const SizedBox(width: 3),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.5),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: Text(
                seconds,
                key: ValueKey<String>(seconds),
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  height: 1.05,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                  fontFeatures: figures,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeBadge() {
    final time = InternetTimeService.instance;
    final synced = time.isSynced;
    final stale = synced &&
        (!time.isHealthy || time.syncAgeSeconds > _staleAfter.inSeconds);
    final color = !synced
        ? ui.AppColors.error
        : stale
            ? ui.AppColors.warning
            : ui.AppColors.success;
    final label = !synced
        ? 'Time not synced'
        : 'Internet time · ${time.sourceLabel} · ±${time.accuracyMs} ms';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ui.AppSpace.sm,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(ui.AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            !synced
                ? Icons.gpp_bad_rounded
                : (stale ? Icons.schedule_rounded : Icons.verified_rounded),
            size: 13,
            color: color,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ui.AppType.micro.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWindowRow(ShiftWindow? window) {
    final shift = window?.shift;
    final chip = _windowChip(window);

    return Row(
      children: [
        Icon(
          ui.AppIcons.clock,
          size: 15,
          color: Colors.white.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 6),
        Text(
          shift == null ? '—  –  —' : shift.label,
          style: ui.AppType.bodyStrong.copyWith(
            color: Colors.white,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const Spacer(),
        Flexible(
          child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: chip.color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(ui.AppRadius.pill),
                border: Border.all(color: chip.color.withValues(alpha: 0.45)),
              ),
              child: Text(
                chip.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ui.AppType.micro.copyWith(
                  color: chip.color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  ({String label, Color color}) _windowChip(ShiftWindow? window) {
    final now = _localNow;
    if (now == null) {
      return (label: 'Waiting for internet time', color: Colors.white70);
    }
    if (window == null) {
      return (label: 'Shift window unavailable', color: Colors.white70);
    }
    if (window.shift == null) {
      return (label: 'No shift assigned', color: ui.AppColors.warning);
    }

    final service = ShiftWindowService.instance;
    final state = service.evaluateLocally(now, isCheckOut: _isOutSide);
    final deadline = service.deadlineFor(isCheckOut: _isOutSide, at: now);
    final closesAt = deadline == null
        ? null
        : DateFormat('HH:mm').format(deadline.toLocal());
    final openUntil = closesAt == null
        ? 'Check-out open'
        : 'Check-out open until $closesAt';

    switch (state) {
      case WindowState.noShift:
        return (label: 'No shift assigned', color: ui.AppColors.warning);
      case WindowState.after:
        if (_isOutSide) {
          return (label: 'Out window closed', color: ui.AppColors.error);
        }
        return (
          label: closesAt == null
              ? 'Check-in closed'
              : 'Check-in closed at $closesAt',
          color: ui.AppColors.error,
        );
      case WindowState.late:
        if (_isOutSide) {
          return (label: openUntil, color: ui.AppColors.success);
        }
        return (
          label: 'Late by ${service.lateMinutesAt(now, isCheckOut: false)} min',
          color: ui.AppColors.warning,
        );
      case WindowState.before:
        if (_isOutSide) {
          return (label: openUntil, color: ui.AppColors.success);
        }
        final opensAt = window.shift!.startAt(now);
        return (
          label: opensAt == null
              ? 'Check-in not open yet'
              : 'Check-in opens at ${DateFormat('HH:mm').format(opensAt)}',
          color: ui.AppColors.accent,
        );
      case WindowState.open:
        if (_isOutSide) {
          return (label: openUntil, color: ui.AppColors.success);
        }
        final remaining = service.remainingText(isCheckOut: false);
        return (
          label: remaining == null
              ? 'Check-in open'
              : 'Check-in open · closes in $remaining',
          color: ui.AppColors.success,
        );
    }
  }

  Widget _buildPunchRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildPunchAction(isCheckOut: false)),
        const SizedBox(width: ui.AppSpace.sm),
        Expanded(child: _buildPunchAction(isCheckOut: true)),
      ],
    );
  }

  Widget _buildPunchAction({required bool isCheckOut}) {
    final reason = _blockReason(isCheckOut: isCheckOut);
    final enabled = reason == null && !widget.busy;
    final punchTime = isCheckOut ? widget.checkOutTime : widget.checkInTime;
    final label = isCheckOut
        ? (punchTime == '--' ? 'Check out' : 'Update out')
        : (punchTime == '--' ? 'Check in' : 'Re-check in');
    final icon = isCheckOut ? Icons.logout_rounded : Icons.login_rounded;
    final punchText = punchTime == '--'
        ? (isCheckOut ? 'No check-out yet' : 'No check-in yet')
        : '${isCheckOut ? 'Out' : 'In'} $punchTime';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: enabled ? Colors.white : Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(ui.AppRadius.md + 2),
          child: InkWell(
            onTap: enabled ? () => _handleTap(isCheckOut) : null,
            borderRadius: BorderRadius.circular(ui.AppRadius.md + 2),
            child: Container(
              height: 46,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: ui.AppSpace.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: enabled
                        ? ui.AppColors.primaryDark
                        : Colors.white.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ui.AppType.bodyStrong.copyWith(
                        color: enabled
                            ? ui.AppColors.primaryDark
                            : Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SyncingTime(
          syncing: isCheckOut ? widget.syncingCheckOut : widget.syncingCheckIn,
          child: Text(
            punchText,
            style: ui.AppType.micro.copyWith(
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ),
        if (reason != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              reason,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: ui.AppType.micro.copyWith(
                color: ui.AppColors.warning,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  /// True when the card is reporting on the check-out side.
  bool get _isOutSide => widget.checkInTime != '--' || widget.canCheckOut;

  void _handleTap(bool isCheckOut) {
    final now = _readInternetTime();
    final window = ShiftWindowService.instance.window.value;
    final state = now == null || window == null
        ? null
        : ShiftWindowService.instance.evaluateLocally(
            now,
            isCheckOut: isCheckOut,
          );
    if (isCheckOut) {
      widget.onCheckOut(state);
    } else {
      widget.onCheckIn(state);
    }
  }

  /// One line saying why this side cannot be punched right now.
  ///
  /// The order matches what the check-in screen enforces: the day state, the
  /// identity the device can offer, the network clock, the window, then the fix.
  String? _blockReason({required bool isCheckOut}) {
    if (widget.isDayComplete) return 'Today already logged';
    if (!isCheckOut && !widget.canCheckIn) return 'Already checked in';
    if (isCheckOut && !widget.canCheckOut) return 'Check in first';

    if (!widget.faceRegistered && !widget.fingerprintEnrolled) {
      return 'Face and fingerprint not enrolled';
    }

    final time = InternetTimeService.instance;
    if (!time.isSynced) return 'Time not synced';
    if (!time.isHealthy || time.syncAgeSeconds > _staleAfter.inSeconds) {
      return 'Time sync stale · retry';
    }

    final window = ShiftWindowService.instance.blockReason(
      isCheckOut: isCheckOut,
    );
    if (window != null) {
      // The full reason is long; the button gets the part that names the cause.
      return window.split(' · ').first;
    }

    return _gpsReason;
  }
}
