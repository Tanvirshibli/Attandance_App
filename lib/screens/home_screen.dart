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
import '../services/attendance_request_service.dart';
import '../services/attendance_stats_service.dart';
import '../services/attendance_punch_notifier.dart';
import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../services/biometric_auth_service.dart';
import '../services/biometric_preferences_service.dart';
import '../services/face_recognition_service.dart';
import '../services/shift_window_service.dart';
import '../services/transaction_ui_service.dart';
import '../widgets/attendance_clock_card.dart';
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
  final AuthService _authService = AuthService();
  final FaceRecognitionService _faceService = FaceRecognitionService();

  bool _canPunchIn = false;
  bool _canPunchOut = false;
  bool _isDayComplete = false;
  bool _checkFlowOpening = false;
  bool _awaitingCheckOutSync = false;
  DateTime? _recentLocalPunchAt;
  String _checkInTime = '--';
  String _checkOutTime = '--';
  List<AttendanceRequestRecord> _requestedRecords = const [];
  AttendanceRequestRecord? _lastLocalTodayRecord;
  AttendanceSummary _summary = const AttendanceSummary();
  List<double> _weeklyHours = List<double>.filled(7, 0);
  AuthUserProfile _profile = AuthUserProfile.fallback();
  bool _isLoadingProfile = true;
  bool _faceRegistered = true;

  /// Cached so the check-in chooser can open without waiting on the platform
  /// channel. A device with no working sensor must not be offered fingerprint.
  bool _fingerprintAvailable = false;

  /// True while a punch is still being submitted in the background, so the
  /// matching time on today's card can pulse until it settles.
  bool _syncingCheckIn = false;
  bool _syncingCheckOut = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AttendancePunchNotifier.revision.addListener(_onPunchSubmitted);
    _lastResumeRefresh = DateTime.now();
    _refreshHomeData();
  }

  @override
  void dispose() {
    AttendancePunchNotifier.revision.removeListener(_onPunchSubmitted);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The check-in screen submits its punch in the background after popping, so
  /// this re-syncs once it lands — and warns when it did not reach the server.
  void _onPunchSubmitted() {
    if (!mounted) return;
    if (!AttendancePunchNotifier.lastSucceeded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AttendancePunchNotifier.lastFailureMessage ??
                'Attendance could not be submitted. Please retry.',
          ),
        ),
      );
    }
    unawaited(
      _loadAttendanceRequestsWithRetry(
        requireCheckOut: AttendancePunchNotifier.lastWasCheckOut,
      ).whenComplete(() {
        // The real row has landed (or the submission failed): stop pulsing.
        if (mounted) {
          setState(() {
            _syncingCheckIn = false;
            _syncingCheckOut = false;
          });
        }
        // The window's deadlines move with the punch (late, closed, next side),
        // so the card must not keep showing the pre-punch copy.
        unawaited(ShiftWindowService.instance.ensure(force: true));
      }),
    );
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
    unawaited(_refreshFingerprintCapability());
    unawaited(_ensureBiometricsReady());
    final employeeId = await _loadProfile();

    if (!mounted) return;

    final recordsDone = _loadAttendanceRecords(employeeId);

    await Future.wait([
      recordsDone,
      _loadSummary(employeeId, recordsDone),
    ]);
  }

  /// Applies the one-time biometric defaults and enrols this phone's
  /// fingerprint, asking once.
  ///
  /// Runs here as well as on the login screen because a session can be restored
  /// without passing through the login form (a saved token, an update install),
  /// and biometrics must end up on either way. Every step is idempotent.
  Future<void> _ensureBiometricsReady() async {
    try {
      await BiometricPreferencesService.instance.applyDefaultsOnce();
      if (!mounted) return;
      if (AppSettingsService.instance.hasBiometricCredential) return;

      final result = await BiometricAuthService.instance.ensureEnrolled(
        confirm: (title, message) async {
          if (!mounted) return false;
          final answer = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(title),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Not now'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Enable'),
                ),
              ],
            ),
          );
          return answer ?? false;
        },
      );
      if (!mounted) return;
      if (result.success) {
        await _refreshFingerprintCapability();
      }
    } catch (error) {
      debugPrint('HomeScreen: biometric preparation failed ($error)');
    }
  }

  /// Kept warm so neither the card nor the method chooser waits on the platform
  /// channel, and so a device without a working sensor never offers fingerprint.
  Future<void> _refreshFingerprintCapability() async {
    bool available = false;
    try {
      final availability = await BiometricAuthService.instance.availability();
      available = availability.available;
    } catch (error) {
      debugPrint('Fingerprint capability check failed: $error');
      available = false;
    }
    if (!mounted || _fingerprintAvailable == available) return;
    setState(() => _fingerprintAvailable = available);
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
    final isDayComplete = todayRecord?.isDayComplete ?? false;

    setState(() {
      _requestedRecords = records;
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

      _weeklyHours = _computeWeeklyHours(records);
      _canPunchIn = canPunchIn;
      _canPunchOut = canPunchOut;
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
  /// The counting itself lives in [AttendanceStatsService] so this screen, the
  /// history list and the report cannot disagree about the same month. The punch
  /// records are only *evidence* here — a day with a real punch is present even
  /// when HRM marks it absent — so the wait on [recordsDone] is about having them
  /// in hand, not about deciding anything.
  Future<void> _loadSummary(int? employeeId, [Future<void>? recordsDone]) async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, 1);
    final to = DateTime(now.year, now.month + 1, 0);

    // The classification reads the punch records, and those arrive from the
    // concurrent load above. Classifying before they land would judge the month
    // against the previous refresh's punches — or against an empty list on a
    // first load, which reports the whole month absent.
    await recordsDone;

    if (!mounted) return;

    final summary = await AttendanceStatsService.instance.load(
      employeeId: employeeId ?? 0,
      from: from,
      to: to,
      punchRecords: _requestedRecords,
      joinedOn: _profile.joinedOn,
    );

    if (!mounted) return;
    setState(() => _summary = summary);
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

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Why a punch cannot start, or null when it can.
  ///
  /// Evaluated twice per tap: once on cached state so the method chooser opens
  /// without waiting, and once after the background reload so the officer is
  /// never sent into a face scan for a punch that will be refused.
  String? _punchBlockReason(bool isCheckOut) {
    if (_isDayComplete) return 'Today\'s attendance is already logged.';
    if (isCheckOut && !_canPunchOut) {
      return 'You need to check in first before checking out.';
    }
    if (!isCheckOut && !_canPunchIn) {
      return 'You are already checked in. Use Check Out.';
    }
    // The server owns the window and re-checks every punch; this only stops the
    // officer sitting through a face scan for a punch that will be refused.
    return ShiftWindowService.instance.blockReason(isCheckOut: isCheckOut);
  }

  Future<void> _openCheckFlow({
    required bool isCheckOut,
    WindowState? windowState,
  }) async {
    if (_checkFlowOpening) return;

    // The card already knows the window it drew the button for; a tap that
    // arrives after it closed is refused here, before the punch list reload.
    // Check-out is exempt: it is never refused on the window.
    if (!isCheckOut &&
        (windowState == WindowState.after ||
            windowState == WindowState.noShift)) {
      _showSnack(
        ShiftWindowService.instance.blockReason(isCheckOut: isCheckOut) ??
            'The check-in window is closed.',
      );
      return;
    }

    // Cached state decides what to offer. The freshness reload used to be
    // awaited here, and that round-trip was the entire delay before the method
    // chooser appeared; it now runs alongside the dialog instead.
    final cachedBlock = _punchBlockReason(isCheckOut);
    if (cachedBlock != null) {
      _showSnack(cachedBlock);
      return;
    }

    final refresh = _loadAttendanceRecords(_profile.canonicalEmployeeId);

    final settings = AppSettingsService.instance;
    // Cached on the last refresh: awaiting the face service here is what made
    // the method chooser appear late.
    final faceRegistered = _faceRegistered;

    final fingerprintReady =
        _fingerprintAvailable &&
            settings.biometricCheckinFingerprint.value &&
            settings.hasBiometricCredential;
    final faceReady = settings.biometricCheckinFace.value && faceRegistered;

    var method = BiometricMethod.face;
    if (!faceRegistered && !fingerprintReady) {
      await _openFaceRegistration();
      if (!mounted) return;
      final nowRegistered = await _faceService.isFaceRegistered();
      if (!nowRegistered) return;
    } else if (faceReady && fingerprintReady) {
      final chosen = await _chooseBiometricMethod();
      if (!mounted || chosen == null) return;
      method = chosen;
    } else if (fingerprintReady) {
      method = BiometricMethod.fingerprint;
    }

    // The dialog is answered; only now is the reload worth waiting for, so a
    // stale cache cannot start a face scan for a punch the server will refuse.
    await refresh;
    if (!mounted) return;
    final freshBlock = _punchBlockReason(isCheckOut);
    if (freshBlock != null) {
      _showSnack(freshBlock);
      return;
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
              builder: (_) =>
                  CheckInScreen(isCheckOut: isCheckOut, method: method),
            ),
          );
      if (punched != null) {
        _applyAttendanceRecord(punched);
        // The punch is still being submitted in the background: pulse the
        // matching time until it lands and the list re-syncs.
        setState(() {
          _syncingCheckIn = !isCheckOut;
          _syncingCheckOut = isCheckOut;
        });
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

  /// Both check-in methods are enabled, so let the officer pick. Dismissing the
  /// sheet cancels the punch rather than guessing.
  Future<BiometricMethod?> _chooseBiometricMethod() {
    // A dialog, not a bottom sheet: the choice belongs in the middle of the
    // screen for a punch. Nothing else in the app uses this helper.
    return showDialog<BiometricMethod>(
      context: context,
      builder: (sheetContext) => Dialog(
        backgroundColor: legacy.AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: legacy.AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Verify with',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: legacy.AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            ListTile(
              leading: const Icon(
                Icons.face_retouching_natural_rounded,
                color: ui.AppColors.mHr,
              ),
              title: Text(
                'Face recognition',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: legacy.AppColors.textPrimary,
                ),
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(BiometricMethod.face),
            ),
            if (_fingerprintAvailable)
              ListTile(
                leading: const Icon(
                  Icons.fingerprint_rounded,
                  color: ui.AppColors.mGeo,
                ),
                title: Text(
                  'Fingerprint',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: legacy.AppColors.textPrimary,
                  ),
                ),
                onTap: () => Navigator.of(sheetContext)
                    .pop(BiometricMethod.fingerprint),
              ),
            const SizedBox(height: 8),
          ],
        ),
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: legacy.AppColors.background,
      body: RefreshIndicator(
        onRefresh: () => TransactionUiService.instance.run(
          _refreshHomeData,
          label: 'Refreshing',
        ),
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
                child: _buildAttendanceClockCard(),
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
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStats() {
    // Present and Absent are two halves of one answer: every counted day lands
    // in exactly one bucket, so showing a solid Present beside a dashed Absent
    // claims a precision the data does not have. When HRM's rows are missing the
    // Absent figure is unknown (its rows are what say "not here"), so Present
    // carries the same dash.
    final absentKnown = !_summary.rowsUnknown;
    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: 'Present',
            value: absentKnown ? '${_summary.presentCount}' : '—',
            icon: Icons.check_circle_outline,
            color: legacy.AppColors.success,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'Absent',
            value: absentKnown ? '${_summary.absentCount}' : '—',
            icon: Icons.cancel_outlined,
            color: legacy.AppColors.error,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'Holiday',
            value: _summary.holidaysUnknown ? '—' : '${_summary.holidayCount}',
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

  /// One card for the clock, the shift window and both punches.
  ///
  /// It owns its own ticking and window chip, so neither the dashboard nor the
  /// attendance list is rebuilt every second.
  Widget _buildAttendanceClockCard() {
    final settings = AppSettingsService.instance;
    return AttendanceClockCard(
      canCheckIn: _canPunchIn,
      canCheckOut: _canPunchOut,
      isDayComplete: _isDayComplete,
      checkInTime: _checkInTime,
      checkOutTime: _checkOutTime,
      syncingCheckIn: _syncingCheckIn,
      syncingCheckOut: _syncingCheckOut,
      faceRegistered: _faceRegistered,
      fingerprintEnrolled: settings.biometricCheckinFingerprint.value &&
          settings.hasBiometricCredential,
      busy: _checkFlowOpening,
      onCheckIn: (state) =>
          _openCheckFlow(isCheckOut: false, windowState: state),
      onCheckOut: (state) =>
          _openCheckFlow(isCheckOut: true, windowState: state),
    );
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

