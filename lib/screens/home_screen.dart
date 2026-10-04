import 'dart:async';

import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';

// This screen is mid-migration: the un-migrated parts still read the legacy
// `AppColors` from theme.dart, while the new card uses the new kit. The new
// tokens come in under a prefix so both can coexist without renaming one of
// them; the whole import collapses when the rest of the file is migrated.
import '../config/theme.dart' as legacy;
import '../widgets/ui/ui.dart' as ui;
import '../models/attendance_request_record.dart';
import '../models/attendance_summary.dart';
import '../models/auth_user_profile.dart';
import '../services/attendance_report_service.dart';
import '../services/attendance_request_service.dart';
import '../services/auth_service.dart';
import '../services/face_recognition_service.dart';
import '../widgets/stat_card.dart';
import '../widgets/attendance_tile.dart';
import 'check_in_screen.dart';
import 'face_registration_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final AttendanceRequestService _attendanceRequestService =
      AttendanceRequestService();
  final AttendanceReportService _reportService = AttendanceReportService();
  final AuthService _authService = AuthService();
  final FaceRecognitionService _faceService = FaceRecognitionService();

  bool _canPunchIn = false;
  bool _canPunchOut = false;
  bool _isClockedIn = false;
  bool _isDayComplete = false;
  bool _checkFlowOpening = false;
  bool _awaitingCheckOutSync = false;
  DateTime? _recentLocalPunchAt;
  bool _todayPendingApproval = false;
  bool _todayApproved = false;
  String _checkInTime = '--';
  String _checkOutTime = '--';
  String _todayWorkHours = '--';
  List<AttendanceRequestRecord> _requestedRecords = const [];
  AttendanceRequestRecord? _lastLocalTodayRecord;
  AttendanceSummary _summary = const AttendanceSummary();
  List<double> _weeklyHours = List<double>.filled(7, 0);
  AuthUserProfile _profile = AuthUserProfile.fallback();
  bool _isLoadingProfile = true;
  bool _faceRegistered = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastResumeRefresh = DateTime.now();
    _refreshHomeData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshHomeDataOnResume();
    }
  }

  /// Refreshes on resume, but not on every one.
  ///
  /// Returning from the camera, the face-registration screen or a Settings trip
  /// all fire `resumed`, and each one used to kick off a full reload — four
  /// attendance requests across two backends. Leaving and re-entering the app
  /// repeatedly on a weak connection could keep it permanently refreshing. The
  /// throttle keeps a genuine change (a long gap) refreshing while collapsing
  /// the bursts, and pull-to-refresh bypasses it because there the user has
  /// explicitly asked for fresh data.
  static const _resumeThrottle = Duration(seconds: 30);

  DateTime? _lastResumeRefresh;

  Future<void> _refreshHomeDataOnResume() async {
    final last = _lastResumeRefresh;
    final now = DateTime.now();

    if (last != null && now.difference(last) < _resumeThrottle) {
      return;
    }

    _lastResumeRefresh = now;
    await _refreshHomeData();
  }

  /// Profile, then the punch list and the month summary together.
  ///
  /// The summary and the punch list do not depend on each other for their
  /// network calls — both only need the employee id — so they are fetched
  /// concurrently. They used to run one after the other, which meant the KPI
  /// cards waited on a full attendance fetch (four requests across two backends)
  /// that they never read.
  Future<void> _refreshHomeData() async {
    final employeeId = await _loadProfile();

    if (!mounted) return;

    final recordsDone = _loadAttendanceRecords(employeeId);

    await Future.wait([
      recordsDone,
      _loadSummary(employeeId, recordsDone),
    ]);
  }

  /// Returns the employee id, or null when the profile could not be resolved.
  Future<int?> _loadProfile() async {
    // Warm the face engine while the dashboard is on screen, so a later tap on
    // check-in opens straight into a usable camera instead of loading on demand.
    unawaited(_faceService.initialize());

    try {
      final profile = await _authService.getCurrentUserProfile();

      if (profile != null) {
        _faceService.hydrateRegistration(profile.faceRegistration);
      }

      final registered = await _faceService.isFaceRegistered();

      if (!mounted) return null;

      setState(() {
        _profile = profile ?? AuthUserProfile.fallback();
        _isLoadingProfile = false;
        _faceRegistered = registered;
      });

      return _profile.canonicalEmployeeId;
    } catch (_) {
      if (!mounted) return null;

      final registered = await _faceService.isFaceRegistered();
      if (!mounted) return null;

      setState(() {
        _profile = AuthUserProfile.fallback();
        _isLoadingProfile = false;
        _faceRegistered = registered;
      });

      return null;
    }
  }

  Future<void> _loadAttendanceRecords(int? employeeId) async {
    // The id can be missing if the profile request failed. Worth one retry, but
    // not worth blocking on: the screen still renders, just without records.
    var resolvedId = employeeId;
    if (resolvedId == null) {
      final profile = await _authService.getCurrentUserProfile();
      if (!mounted) return;

      if (profile != null) {
        resolvedId = profile.canonicalEmployeeId;
        setState(() {
          _profile = profile;
          _isLoadingProfile = false;
        });
      }
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final records = await _attendanceRequestService.getHomeAttendanceRecords(
      employeeId: resolvedId,
    );
    if (!mounted) return;

    _applyRecordsToHomeState(records, today, preserveLocal: true);
  }

  Future<void> _loadAttendanceRequestsWithRetry({
    int attempts = 5,
    bool requireCheckOut = false,
  }) async {
    for (var i = 0; i < attempts; i++) {
      // Only the punch list is re-fetched here. This runs after a punch, to
      // wait for the record to appear on the backend, so re-running the whole
      // dashboard refresh would only repeat work that has not changed.
      await _loadAttendanceRecords(_profile.canonicalEmployeeId);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final todayRecord = _attendanceRequestService.resolveTodayRecord(
        _requestedRecords,
        today,
      );

      final hasRequiredIn = todayRecord != null && todayRecord.hasCheckIn;
      final hasRequiredOut =
          !requireCheckOut || (todayRecord != null && todayRecord.hasCheckOut);

      if (hasRequiredIn && hasRequiredOut) {
        if (requireCheckOut) {
          _awaitingCheckOutSync = false;
        }
        break;
      }

      if (i < attempts - 1) {
        await Future.delayed(Duration(milliseconds: 400 + (i * 400)));
      }
    }
  }

  bool _isRecentLocalPunch() {
    final punchedAt = _recentLocalPunchAt;
    if (punchedAt == null) return false;
    return DateTime.now().difference(punchedAt) <= const Duration(minutes: 2);
  }

  void _applyRecordsToHomeState(
    List<AttendanceRequestRecord> records,
    DateTime today, {
    bool preserveLocal = false,
  }) {
    var todayRecord = _attendanceRequestService.resolveTodayRecord(
      records,
      today,
    );

    if (preserveLocal && _lastLocalTodayRecord != null) {
      if (todayRecord == null) {
        todayRecord = _lastLocalTodayRecord;
      } else if (!todayRecord.hasCheckIn && _lastLocalTodayRecord!.hasCheckIn) {
        todayRecord = _attendanceRequestService.mergeRecords([
          _lastLocalTodayRecord!,
          todayRecord,
        ], preferDay: today);
      } else if (_isRecentLocalPunch() &&
          _lastLocalTodayRecord!.hasCheckOut &&
          todayRecord.hasCheckIn &&
          !todayRecord.hasCheckOut) {
        todayRecord = _attendanceRequestService.mergeRecords([
          _lastLocalTodayRecord!,
          todayRecord,
        ], preferDay: today);
      } else if (todayRecord.hasCheckIn &&
          !todayRecord.hasCheckOut &&
          _lastLocalTodayRecord!.hasCheckOut) {
        _lastLocalTodayRecord = todayRecord;
      }
    }

    if (todayRecord != null &&
        (todayRecord.hasCheckIn || todayRecord.hasCheckOut)) {
      if (todayRecord.hasCheckIn &&
          (!todayRecord.hasCheckOut || _isRecentLocalPunch())) {
        _lastLocalTodayRecord = todayRecord;
      } else if (!todayRecord.hasCheckOut) {
        _lastLocalTodayRecord = todayRecord;
      }
    } else {
      _lastLocalTodayRecord = null;
    }

    final canPunchIn = todayRecord?.canPunchCheckIn ?? true;
    final canPunchOut = todayRecord?.canPunchCheckOut ?? false;
    final isClockedIn = canPunchOut;
    final isDayComplete = todayRecord?.isDayComplete ?? false;
    final pendingApproval =
        todayRecord != null &&
        todayRecord.status.toLowerCase() == 'requested' &&
        !todayRecord.isRejected;
    final approved =
        todayRecord != null &&
        todayRecord.status.toLowerCase() == 'approved' &&
        !todayRecord.isRejected;

    setState(() {
      _requestedRecords = records;
      _todayPendingApproval = pendingApproval;
      _todayApproved = approved;
      if (todayRecord != null && todayRecord.hasCheckIn) {
        _checkInTime = todayRecord.checkInText;
      } else {
        _checkInTime = '--';
      }

      if (todayRecord != null && todayRecord.hasCheckOut) {
        _checkOutTime = todayRecord.checkOutText;
      } else {
        _checkOutTime = '--';
      }

      _todayWorkHours = _computeTodayHours(todayRecord);
      _weeklyHours = _computeWeeklyHours(records);
      _canPunchIn = canPunchIn;
      _canPunchOut = canPunchOut;
      _isClockedIn = isClockedIn;
      _isDayComplete = isDayComplete;
    });
  }

  void _applyAttendanceRecord(AttendanceRequestRecord punched) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (!punched.matchesCalendarDay(today)) return;

    _recentLocalPunchAt = now;
    _lastLocalTodayRecord = punched;

    final updated = List<AttendanceRequestRecord>.from(_requestedRecords);
    final existingToday = _attendanceRequestService.resolveTodayRecord(
      updated,
      today,
    );
    if (existingToday != null) {
      final merged = _attendanceRequestService.mergeRecords([
        existingToday,
        punched,
      ], preferDay: today);
      final idx = updated.indexWhere(
        (record) => record.matchesCalendarDay(today),
      );
      if (idx >= 0) {
        updated[idx] = merged;
      } else {
        updated.insert(0, merged);
      }
    } else {
      updated.insert(0, punched);
    }

    _applyRecordsToHomeState(updated, today);
  }

  /// Loads the month KPIs.
  ///
  /// [recordsDone] is the concurrent punch-list load. The backend call starts
  /// immediately, so the two requests genuinely overlap, but the decision about
  /// which value to trust reads the punch records — so that part has to wait for
  /// [recordsDone] before it can be made.
  Future<void> _loadSummary(int? employeeId, [Future<void>? recordsDone]) async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, 1);
    final to = DateTime(now.year, now.month + 1, 0);

    AttendanceSummary? fetched;

    // Without an id there is nothing to ask the backend about; the fallback
    // below still produces a usable estimate from the punch records.
    if (employeeId != null && employeeId > 0) {
      final result = await _reportService.getSummary(
        employeeId: employeeId,
        from: from,
        to: to,
      );

      if (result.success && result.data != null) {
        fetched = result.data;
      }
    }

    // Both the decision below and the reconciliation read the punch records, and
    // those arrive from the concurrent load above. Judging the backend response
    // before they land would compare it against the *previous* refresh's rows —
    // or against an empty list on a first load.
    await recordsDone;

    if (!mounted) return;

    final summary = fetched;

    if (summary != null &&
        summary.parsedFromKnownShape &&
        (summary.hasAnyKpi || _monthPunchPresentDays(from, to) == 0)) {
      setState(
        () => _summary = summary.reconciledWithPunchDays(_punchDays()),
      );
      return;
    }

    setState(
      () => _summary = _summaryFromPunchRecords(
        from,
        to,
      ).reconciledWithPunchDays(_punchDays()),
    );
  }

  /// Calendar days with a non-rejected punch this employee made.
  Set<DateTime> _punchDays() {
    final days = <DateTime>{};
    for (final record in _requestedRecords) {
      if (record.isRejected) continue;
      if (!record.hasCheckIn && !record.hasCheckOut) continue;
      final day = record.effectiveCalendarDay;
      if (day == null) continue;
      days.add(DateTime(day.year, day.month, day.day));
    }
    return days;
  }

  int _monthPunchPresentDays(DateTime from, DateTime to) {
    final days = <String>{};
    for (final record in _requestedRecords) {
      if (!record.hasCheckIn || record.isRejected) continue;
      final day = record.effectiveCalendarDay;
      if (day == null) continue;
      if (day.isBefore(from) || day.isAfter(to)) continue;
      days.add(
        '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}',
      );
    }
    return days.length;
  }

  AttendanceSummary _summaryFromPunchRecords(DateTime from, DateTime to) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = to.isBefore(today) ? to : today;
    final punched = _punchDays();

    // Days in [from, today] without any punch count as absent.
    var absentDays = 0;
    for (var i = 0; ; i++) {
      final day = DateTime(from.year, from.month, from.day + i);
      if (day.isAfter(end)) break;
      if (!punched.contains(day)) absentDays++;
    }

    return AttendanceSummary.fromPunchRecords(
      presentDays: _monthPunchPresentDays(from, to),
      absentDays: absentDays,
    );
  }

  String _computeTodayHours(AttendanceRequestRecord? todayRecord) {
    if (todayRecord == null) return '--';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final hours = todayRecord.workedHoursOnDay(today, now: now);
    if (hours == null) return '--';
    return hours.toStringAsFixed(1);
  }

  List<double> _computeWeeklyHours(List<AttendanceRequestRecord> records) {
    final hours = List<double>.filled(7, 0);
    final now = DateTime.now();
    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));

    for (final record in records) {
      final day = record.effectiveCalendarDay;
      if (day == null) continue;
      final diff = day.difference(monday).inDays;
      if (diff < 0 || diff > 6) continue;

      final dayHours = record.workedHoursOnDay(day, now: now);
      if (dayHours == null) continue;
      hours[diff] += dayHours;
    }
    return hours;
  }

  Future<void> _openCheckFlow({required bool isCheckOut}) async {
    if (_checkFlowOpening) return;

    // Re-read the punch list before deciding what to offer: the buttons on this
    // screen depend on it, and the cached copy can be minutes old.
    await _loadAttendanceRecords(_profile.canonicalEmployeeId);
    if (!mounted) return;

    if (_isDayComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Today\'s attendance is already logged.')),
      );
      return;
    }

    if (isCheckOut && !_canPunchOut) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You need to check in first before checking out.'),
        ),
      );
      return;
    }

    if (!isCheckOut && !_canPunchIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are already checked in. Use Check Out.'),
        ),
      );
      return;
    }

    final registered = await _faceService.isFaceRegistered();
    if (!mounted) return;
    if (!registered) {
      await _openFaceRegistration();
      if (!mounted) return;
      final nowRegistered = await _faceService.isFaceRegistered();
      if (!nowRegistered) return;
    }

    setState(() {
      _checkFlowOpening = true;
      if (isCheckOut) {
        _awaitingCheckOutSync = true;
      }
    });
    if (!mounted) return;
    try {
      final punched = await Navigator.of(context)
          .push<AttendanceRequestRecord?>(
            MaterialPageRoute(
              builder: (_) => CheckInScreen(isCheckOut: isCheckOut),
            ),
          );
      if (punched != null) {
        _applyAttendanceRecord(punched);
      }
    } finally {
      if (mounted) {
        setState(() => _checkFlowOpening = false);
      }
      await _loadAttendanceRequestsWithRetry(
        requireCheckOut: isCheckOut || _awaitingCheckOutSync,
      );
    }
  }

  Future<void> _openFaceRegistration() async {
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const FaceRegistrationScreen()));
    if (!mounted) return;
    final registered = await _faceService.isFaceRegistered();
    if (!mounted) return;
    setState(() => _faceRegistered = registered);
  }

  String _attendanceActionTitle() {
    if (_isDayComplete) {
      return _todayApproved
          ? 'Today\'s Attendance Approved'
          : 'Today\'s Attendance Logged';
    }
    if (_canPunchOut) {
      if (_checkOutTime != '--') {
        return 'Update Check Out?';
      }
      return 'You\'re Clocked In';
    }
    return 'Ready to Check In?';
  }

  String _attendanceActionSubtitle() {
    if (_isDayComplete) {
      if (_todayApproved) {
        return 'Today\'s attendance is complete and approved.';
      }
      if (_checkInTime != '--' && _checkOutTime != '--') {
        return 'Checked in at $_checkInTime, out at $_checkOutTime. Awaiting supervisor approval.';
      }
      return 'Today\'s punch is pending approval.';
    }
    if (_todayApproved) {
      if (_isClockedIn) {
        return 'Checked in at $_checkInTime. Approved — you can check out when ready.';
      }
      if (_checkInTime != '--' || _checkOutTime != '--') {
        return 'Today\'s attendance is approved.';
      }
    }
    if (_todayPendingApproval) {
      if (_isClockedIn) {
        return 'Checked in at $_checkInTime. Pending approval — you can check out when ready.';
      }
      if (_checkInTime != '--' || _checkOutTime != '--') {
        return 'Today\'s punch is pending approval.';
      }
      return 'Your attendance request is pending approval.';
    }
    if (_canPunchOut) {
      if (_checkOutTime != '--') {
        return 'Checked in at $_checkInTime, out at $_checkOutTime. Tap below to update checkout time.';
      }
      return 'Checked in at $_checkInTime. You can check out now.';
    }
    return 'Verify with face + location for check-in/check-out.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: legacy.AppColors.background,
      body: RefreshIndicator(
        onRefresh: _refreshHomeData,
        color: legacy.AppColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            // Custom App Bar
            SliverToBoxAdapter(child: _buildHeader(context)),

            // Quick Stats
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: FadeInUp(
                  delay: const Duration(milliseconds: 200),
                  duration: const Duration(milliseconds: 500),
                  child: _buildQuickStats(),
                ),
              ),
            ),

            if (!_isLoadingProfile && !_faceRegistered)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: FadeInUp(
                    delay: const Duration(milliseconds: 250),
                    duration: const Duration(milliseconds: 500),
                    child: _buildFaceMissingCard(),
                  ),
                ),
              ),

            // Attendance actions
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: FadeInUp(
                  delay: const Duration(milliseconds: 300),
                  duration: const Duration(milliseconds: 500),
                  child: _buildAttendanceActionCard(context),
                ),
              ),
            ),

            // Weekly Chart
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: FadeInUp(
                  delay: const Duration(milliseconds: 400),
                  duration: const Duration(milliseconds: 500),
                  child: _buildWeeklyChart(),
                ),
              ),
            ),

            // Recent Attendance
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: FadeInUp(
                  delay: const Duration(milliseconds: 500),
                  duration: const Duration(milliseconds: 500),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recent Attendance',
                        style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: legacy.AppColors.textPrimary,
                        ),
                      ),
                      TextButton(
                        onPressed: () {},
                        child: Text(
                          'View All',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: legacy.AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final record = _requestedRecords[index].toTileRecord();
                  return FadeInUp(
                    delay: Duration(milliseconds: 550 + (index * 50)),
                    duration: const Duration(milliseconds: 400),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: AttendanceTile(record: record),
                    ),
                  );
                },
                childCount: _requestedRecords.length > 5
                    ? 5
                    : _requestedRecords.length,
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 16,
        20,
        24,
      ),
      decoration: const BoxDecoration(
        gradient: legacy.AppColors.primaryGradient,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: FadeInDown(
        duration: const Duration(milliseconds: 500),
        child: Column(
          children: [
            Row(
              children: [
                // Avatar
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _profile.avatarLetters,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Name & greeting
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getGreeting(),
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: Colors.white70,
                        ),
                      ),
                      Text(
                        _isLoadingProfile
                            ? 'Loading profile...'
                            : _profile.name,
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _profile.designation == 'N/A'
                            ? _profile.employeeId
                            : '${_profile.designation} · ${_profile.employeeId}',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Notification bell
                Stack(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.notifications_outlined,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: legacy.AppColors.error,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Today's card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildTodayStat(
                    'Check In',
                    _checkInTime,
                    Icons.login_rounded,
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  _buildTodayStat(
                    'Check Out',
                    _checkOutTime,
                    Icons.logout_rounded,
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  _buildTodayStat(
                    'Hours',
                    _todayWorkHours,
                    Icons.timer_outlined,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(height: 6),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(fontSize: 11, color: Colors.white54),
        ),
      ],
    );
  }

  Widget _buildQuickStats() {
    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: 'Present',
            value: '${_summary.presentCount}',
            icon: Icons.check_circle_outline,
            color: legacy.AppColors.success,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'Absent',
            value: '${_summary.absentCount}',
            icon: Icons.cancel_outlined,
            color: legacy.AppColors.error,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'Holiday',
            value: '${_summary.holidayCount}',
            icon: Icons.celebration_outlined,
            color: legacy.AppColors.warning,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'Leave',
            value: '${_summary.leaveCount}',
            icon: Icons.event_busy_outlined,
            color: legacy.AppColors.info,
          ),
        ),
      ],
    );
  }

  Widget _buildFaceMissingCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: legacy.AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: legacy.AppColors.warning.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your face data is missing or unreadable. Please register your face again.',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: legacy.AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _openFaceRegistration,
              style: ElevatedButton.styleFrom(
                backgroundColor: legacy.AppColors.warning,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Register face',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceActionCard(BuildContext context) {
    // A status colour is a signal, not a surface. The card used to flood a
    // large block with saturated success green, which shouted louder than the
    // "Check Out" button living inside it. Now the state is carried by a thin
    // accent rail, a small status chip and the icon, and the card itself stays
    // on the brand surface so the action reads first.
    final isDone = _isDayComplete;
    final isActive = !isDone && _isClockedIn;
    final stateColor = isDone
        ? (_todayApproved ? ui.AppColors.success : ui.AppColors.warning)
        : (isActive ? ui.AppColors.success : ui.AppColors.primary);

    return Container(
      decoration: BoxDecoration(
        color: ui.AppColors.surface,
        borderRadius: BorderRadius.circular(ui.AppRadius.xl),
        border: Border.all(color: stateColor.withValues(alpha: 0.28)),
        boxShadow: ui.AppShadows.card,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: stateColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(ui.AppSpace.md + 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _attendanceActionTitle(),
                            style: ui.AppType.h3.copyWith(
                              color: ui.AppColors.ink,
                            ),
                          ),
                        ),
                        _StateChip(
                          label: _actionStateLabel(
                            isDone: isDone,
                            isActive: isActive,
                          ),
                          color: stateColor,
                          icon: isDone
                              ? (_todayApproved
                                    ? ui.AppIcons.check
                                    : ui.AppIcons.clock)
                              : (isActive
                                    ? ui.AppIcons.clock
                                    : ui.AppIcons.calendar),
                        ),
                      ],
                    ),
                    const SizedBox(height: ui.AppSpace.xxs),
                    Text(
                      _attendanceActionSubtitle(),
                      style: ui.AppType.meta.copyWith(
                        color: ui.AppColors.inkMuted,
                      ),
                    ),
                    if (isDone) ...[
                      const SizedBox(height: ui.AppSpace.md),
                      Row(
                        children: [
                          Icon(
                            _todayApproved
                                ? Icons.check_circle_outline_rounded
                                : Icons.hourglass_top_rounded,
                            color: stateColor,
                            size: 18,
                          ),
                          const SizedBox(width: ui.AppSpace.xs),
                          Expanded(
                            child: Text(
                              _todayApproved
                                  ? 'No further punches needed today.'
                                  : 'Awaiting supervisor approval.',
                              style: ui.AppType.meta.copyWith(
                                color: ui.AppColors.inkMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: ui.AppSpace.md),
                      if (_canPunchOut)
                        ui.AppButton(
                          label: _checkOutTime != '--'
                              ? 'Update check out'
                              : 'Check out',
                          icon: ui.AppIcons.chevron,
                          onPressed: _checkFlowOpening
                              ? null
                              : () => _openCheckFlow(isCheckOut: true),
                          accent: stateColor,
                        )
                      else if (_canPunchIn)
                        ui.AppButton(
                          label: _checkInTime != '--'
                              ? 'Re-check in'
                              : 'Check in',
                          icon: ui.AppIcons.chevron,
                          onPressed: _checkFlowOpening
                              ? null
                              : () => _openCheckFlow(isCheckOut: false),
                          accent: stateColor,
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _actionStateLabel({required bool isDone, required bool isActive}) {
    if (isDone) return _todayApproved ? 'Complete' : 'Pending';
    if (isActive) return 'Clocked in';
    if (_canPunchIn) return 'Ready';
    return 'Closed';
  }

  Widget _buildWeeklyChart() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: legacy.AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: legacy.AppColors.shadow.withValues(alpha: 0.06),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Weekly Hours',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: legacy.AppColors.textPrimary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: legacy.AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'This Week',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: legacy.AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: 12,
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        final days = [
                          'Mon',
                          'Tue',
                          'Wed',
                          'Thu',
                          'Fri',
                          'Sat',
                          'Sun',
                        ];
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            days[value.toInt()],
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: legacy.AppColors.textHint,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                barGroups: List.generate(7, (index) {
                  final hours = index < _weeklyHours.length
                      ? _weeklyHours[index]
                      : 0.0;
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: hours.clamp(0, 12),
                        color: hours > 0
                            ? legacy.AppColors.primary
                            : legacy.AppColors.divider,
                        width: 22,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(6),
                          topRight: Radius.circular(6),
                        ),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: 12,
                          color: legacy.AppColors.primary.withValues(
                            alpha: 0.06,
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning 👋';
    if (hour < 17) return 'Good Afternoon 👋';
    return 'Good Evening 👋';
  }
}

/// A small, non-interactive state label for the attendance action card.
class _StateChip extends StatelessWidget {
  const _StateChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ui.AppSpace.xs,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ui.AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ui.AppIcon(icon, size: 12, color: color, secondaryOpacity: 0.5),
          const SizedBox(width: ui.AppSpace.xxs),
          Text(
            label,
            style: ui.AppType.micro.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
