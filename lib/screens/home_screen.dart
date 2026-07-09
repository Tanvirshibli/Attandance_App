import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';
import '../models/attendance_request_record.dart';
import '../models/attendance_summary.dart';
import '../models/auth_user_profile.dart';
import '../services/attendance_report_service.dart';
import '../services/attendance_request_service.dart';
import '../services/auth_service.dart';
import '../widgets/stat_card.dart';
import '../widgets/attendance_tile.dart';
import 'check_in_screen.dart';

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

  bool _isClockedIn = false;
  String _checkInTime = '--';
  String _checkOutTime = '--';
  String _todayWorkHours = '--';
  List<AttendanceRequestRecord> _requestedRecords = const [];
  AttendanceSummary _summary = const AttendanceSummary();
  List<double> _weeklyHours = List<double>.filled(7, 0);
  AuthUserProfile _profile = AuthUserProfile.fallback();
  bool _isLoadingProfile = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      _refreshHomeData();
    }
  }

  /// Profile first, then attendance list + summary (avoids employeeId race).
  Future<void> _refreshHomeData() async {
    await _loadProfile();
    if (!mounted) return;
    await _loadAttendanceRequests();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _authService.getCurrentUserProfile();
      if (!mounted) return;

      setState(() {
        _profile = profile ?? AuthUserProfile.fallback();
        _isLoadingProfile = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _profile = AuthUserProfile.fallback();
        _isLoadingProfile = false;
      });
    }
  }

  Future<void> _loadAttendanceRequests() async {
    var employeeId = _profile.canonicalEmployeeId;
    if (employeeId == null) {
      final profile = await _authService.getCurrentUserProfile();
      employeeId = profile?.canonicalEmployeeId;
      if (profile != null && mounted) {
        setState(() {
          _profile = profile;
          _isLoadingProfile = false;
        });
      }
    }

    final records = await _attendanceRequestService.getAttendanceRecords(
      employeeId: employeeId,
    );
    if (!mounted) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    AttendanceRequestRecord? todayRecord;
    for (final record in records) {
      if (record.isSameCalendarDay(today)) {
        todayRecord = record;
        break;
      }
    }

    // Clocked-in is today-only — never use a prior day's open punch.
    final isClockedIn = todayRecord?.canTreatAsActiveCheckIn ?? false;

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

      _todayWorkHours = _computeTodayHours(todayRecord);
      _weeklyHours = _computeWeeklyHours(records);
      _isClockedIn = isClockedIn;
    });

    if (employeeId != null && employeeId > 0) {
      await _loadSummary(employeeId);
    }
  }

  Future<void> _loadSummary(int employeeId) async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, 1);
    final to = DateTime(now.year, now.month + 1, 0);
    final result = await _reportService.getSummary(
      employeeId: employeeId,
      from: from,
      to: to,
    );
    if (!mounted) return;

    if (result.success && result.data != null) {
      final summary = result.data!;
      // Prefer API rows/summary when shape is known and has KPIs, or when
      // there are no local punches to estimate from.
      if (summary.parsedFromKnownShape) {
        if (summary.hasAnyKpi || _monthPunchPresentDays(from, to) == 0) {
          setState(() => _summary = summary);
          return;
        }
      }
    }

    setState(() => _summary = _summaryFromPunchRecords(from, to));
  }

  int _monthPunchPresentDays(DateTime from, DateTime to) {
    final days = <String>{};
    for (final record in _requestedRecords) {
      if (!record.hasCheckIn || record.isRejected) continue;
      final day = record.attDateOnly;
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
    return AttendanceSummary.fromPunchRecords(
      presentDays: _monthPunchPresentDays(from, to),
    );
  }

  String _computeTodayHours(AttendanceRequestRecord? todayRecord) {
    if (todayRecord == null) return '--';
    final inTime =
        AttendanceRequestRecord.parseFlexibleDateTime(todayRecord.requestedInTime);
    final outTime =
        AttendanceRequestRecord.parseFlexibleDateTime(todayRecord.requestedOutTime);
    if (inTime == null) return '--';
    final end = outTime ?? DateTime.now();
    if (end.isBefore(inTime)) return '--';
    final hours = end.difference(inTime).inMinutes / 60.0;
    return hours.toStringAsFixed(1);
  }

  List<double> _computeWeeklyHours(List<AttendanceRequestRecord> records) {
    final hours = List<double>.filled(7, 0);
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));

    for (final record in records) {
      final day = record.attDateOnly;
      if (day == null) continue;
      final diff = day.difference(monday).inDays;
      if (diff < 0 || diff > 6) continue;

      final inTime =
          AttendanceRequestRecord.parseFlexibleDateTime(record.requestedInTime);
      final outTime =
          AttendanceRequestRecord.parseFlexibleDateTime(record.requestedOutTime);
      if (inTime == null) continue;
      final end = outTime ?? now;
      if (end.isBefore(inTime)) continue;
      hours[diff] += end.difference(inTime).inMinutes / 60.0;
    }
    return hours;
  }

  Future<void> _openCheckFlow({required bool isCheckOut}) async {
    await _loadAttendanceRequests();
    if (!mounted) return;

    if (isCheckOut && !_isClockedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You need to check in first before checking out.'),
        ),
      );
      return;
    }

    if (!isCheckOut && _isClockedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are already checked in. Use Check Out.'),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckInScreen(
          isCheckOut: isCheckOut,
          onCheckIn: () {
            setState(() {
              if (isCheckOut) {
                _isClockedIn = false;
                _checkOutTime = TimeOfDay.now().format(context);
              } else {
                _isClockedIn = true;
                _checkInTime = TimeOfDay.now().format(context);
                _checkOutTime = '--';
              }
            });
            _loadAttendanceRequests();
          },
        ),
      ),
    );

    _loadAttendanceRequests();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Custom App Bar
          SliverToBoxAdapter(
            child: _buildHeader(context),
          ),

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
                        color: AppColors.textPrimary,
                      ),
                    ),
                    TextButton(
                      onPressed: () {},
                      child: Text(
                        'View All',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
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

          const SliverToBoxAdapter(
            child: SizedBox(height: 100),
          ),
        ],
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
        gradient: AppColors.primaryGradient,
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
                        _isLoadingProfile ? 'Loading profile...' : _profile.name,
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
                          color: AppColors.error,
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
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildTodayStat('Check In', _checkInTime, Icons.login_rounded),
                  Container(
                    width: 1,
                    height: 40,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  _buildTodayStat(
                      'Check Out', _checkOutTime, Icons.logout_rounded),
                  Container(
                    width: 1,
                    height: 40,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  _buildTodayStat(
                      'Hours', _todayWorkHours, Icons.timer_outlined),
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
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: Colors.white54,
          ),
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
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'Absent',
            value: '${_summary.absentCount}',
            icon: Icons.cancel_outlined,
            color: AppColors.error,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'Holiday',
            value: '${_summary.holidayCount}',
            icon: Icons.celebration_outlined,
            color: AppColors.warning,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'Leave',
            value: '${_summary.leaveCount}',
            icon: Icons.event_busy_outlined,
            color: AppColors.info,
          ),
        ),
      ],
    );
  }

  Widget _buildAttendanceActionCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: _isClockedIn ? AppColors.successGradient : AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (_isClockedIn ? AppColors.success : AppColors.primary)
                .withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isClockedIn ? 'You\'re Clocked In' : 'Ready to Check In?',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _isClockedIn
                ? 'Checked in at $_checkInTime. You can check out now.'
                : 'Verify with face + location for check-in/check-out.',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isClockedIn
                      ? null
                      : () => _openCheckFlow(isCheckOut: false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    disabledBackgroundColor: Colors.white.withValues(alpha: 0.5),
                    disabledForegroundColor: AppColors.textHint,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.login_rounded, size: 20),
                  label: Text(
                    'Check In',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isClockedIn
                      ? () => _openCheckFlow(isCheckOut: true)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppColors.success.withValues(alpha: 0.45),
                    disabledForegroundColor: Colors.white70,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 20),
                  label: Text(
                    'Check Out',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyChart() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withValues(alpha: 0.06),
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
                  color: AppColors.textPrimary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'This Week',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primary,
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
                        final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            days[value.toInt()],
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: AppColors.textHint,
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
                        color: hours > 0 ? AppColors.primary : AppColors.divider,
                        width: 22,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(6),
                          topRight: Radius.circular(6),
                        ),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: 12,
                          color: AppColors.primary.withValues(alpha: 0.06),
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
