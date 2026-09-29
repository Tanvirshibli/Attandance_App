import 'package:flutter/material.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../widgets/ui/ui.dart' as ui;
import '../models/attendance_request_record.dart';
import '../models/attendance_summary.dart';
import '../services/attendance_report_service.dart';
import '../services/attendance_request_service.dart';
import '../services/auth_service.dart';
import '../widgets/attendance_tile.dart';
import 'attendance_report_screen.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  final AttendanceRequestService _attendanceRequestService =
      AttendanceRequestService();
  final AttendanceReportService _reportService = AttendanceReportService();
  final AuthService _authService = AuthService();

  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'Requested', 'Approved', 'Rejected'];
  List<AttendanceRequestRecord> _records = const [];
  AttendanceSummary _summary = const AttendanceSummary();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);
    final profile = await _authService.getCurrentUserProfile();
    final employeeId = profile?.canonicalEmployeeId;
    final records = await _attendanceRequestService.getAttendanceRecords(
      employeeId: employeeId,
    );

    AttendanceSummary summary = const AttendanceSummary();
    if (employeeId != null && employeeId > 0) {
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, 1);
      final to = DateTime(now.year, now.month + 1, 0);
      final result = await _reportService.getSummary(
        employeeId: employeeId,
        from: from,
        to: to,
      );
      if (result.success && result.data != null) {
        summary = result.data!;
      } else {
        final approved =
            records.where((r) => r.status.toLowerCase() == 'approved').length;
        final requested =
            records.where((r) => r.status.toLowerCase() == 'requested').length;
        final rejected =
            records.where((r) => r.status.toLowerCase() == 'rejected').length;
        summary = AttendanceSummary.fromRecords(
          approved: approved,
          requested: requested,
          rejected: rejected,
        );
      }
    }

    // HRM rows can mark punched days absent (mobile punches live in
    // ZKTeco) — move days with a real punch back to present.
    summary = summary.reconciledWithPunchDays(_punchDaysFrom(records));

    if (!mounted) return;
    setState(() {
      _records = records;
      _summary = summary;
      _isLoading = false;
    });
  }

  /// Calendar days with a non-rejected check-in or check-out.
  Set<DateTime> _punchDaysFrom(List<AttendanceRequestRecord> records) {
    final days = <DateTime>{};
    for (final record in records) {
      if (record.isRejected) continue;
      if (!record.hasCheckIn && !record.hasCheckOut) continue;
      final day = record.effectiveCalendarDay;
      if (day == null) continue;
      days.add(DateTime(day.year, day.month, day.day));
    }
    return days;
  }

  double get _attendancePercent {
    final total = _summary.totalDays > 0
        ? _summary.totalDays
        : (_summary.presentCount +
            _summary.absentCount +
            _summary.leaveCount +
            _summary.holidayCount);
    if (total <= 0) return 0;
    return (_summary.presentCount / total).clamp(0.0, 1.0);
  }

  List<Map<String, dynamic>> get _filteredRecords {
    final all = _records.map((item) => item.toTileRecord()).toList();
    if (_selectedFilter == 'All') return all;
    return all
        .where((r) =>
            (r['status'] as String).toLowerCase() ==
            _selectedFilter.toLowerCase())
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ui.AppColors.canvas,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Header card
          SliverToBoxAdapter(
            child: _buildHeader(context),
          ),

          // Month summary
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                ui.AppSpace.gutter,
                ui.AppSpace.xs,
                ui.AppSpace.gutter,
                0,
              ),
              child: _buildMonthlySummary(),
            ),
          ),

          // Filter chips
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                ui.AppSpace.gutter,
                ui.AppSpace.sm,
                0,
                ui.AppSpace.xs,
              ),
              child: _buildFilterChips(),
            ),
          ),

          // Section title
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                ui.AppSpace.gutter,
                ui.AppSpace.sm,
                ui.AppSpace.gutter,
                ui.AppSpace.xs,
              ),
              child: ui.AppSectionTitle(
                title: 'Attendance records',
                subtitle: '${_filteredRecords.length} shown',
                accent: ui.AppColors.mAttendance,
              ),
            ),
          ),

          // Records list
          _filteredRecords.isEmpty
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(ui.AppSpace.xl),
                    child: ui.AppEmptyState(
                      icon: ui.AppIcons.calendar,
                      title: _isLoading ? 'Loading records' : 'No records found',
                      subtitle: _isLoading
                          ? 'Fetching your attendance history.'
                          : 'No attendance records match this filter.',
                      onRetry: _isLoading ? null : _loadRecords,
                    ),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ui.AppSpace.gutter,
                  ),
                  sliver: SliverList.builder(
                    itemCount: _filteredRecords.length,
                    itemBuilder: (context, index) {
                      final record = _filteredRecords[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: ui.AppSpace.xs),
                        child: AttendanceTile(record: record),
                      );
                    },
                  ),
                ),

          const SliverToBoxAdapter(
            child: SizedBox(height: ui.AppSpace.fabClearance),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        ui.AppSpace.gutter,
        MediaQuery.of(context).padding.top + ui.AppSpace.sm,
        ui.AppSpace.gutter,
        ui.AppSpace.md,
      ),
      decoration: const BoxDecoration(
        gradient: ui.AppColors.brandGradient,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(ui.AppRadius.xxl),
          bottomRight: Radius.circular(ui.AppRadius.xxl),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Attendance',
                  style: ui.AppType.h1.copyWith(color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: ui.AppSpace.sm),
              _HeaderAction(
                icon: PhosphorIconsDuotone.chartBar,
                label: 'Full report',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AttendanceReportScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: ui.AppSpace.md),
          Row(
            children: [
              CircularPercentIndicator(
                radius: 42,
                lineWidth: 7,
                percent: _attendancePercent,
                center: Text(
                  '${(_attendancePercent * 100).toStringAsFixed(0)}%',
                  style: ui.AppType.h3.copyWith(color: Colors.white),
                ),
                progressColor: ui.AppColors.primaryLight,
                backgroundColor: Colors.white.withValues(alpha: 0.22),
                circularStrokeCap: CircularStrokeCap.round,
              ),
              const SizedBox(width: ui.AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Monthly overview',
                      style: ui.AppType.h3.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_summary.presentCount} present · '
                      '${_summary.totalDays > 0 ? _summary.totalDays : (_summary.presentCount + _summary.absentCount + _summary.leaveCount)} days tracked',
                      style: ui.AppType.meta.copyWith(
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlySummary() {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: ui.AppSpace.md,
        horizontal: ui.AppSpace.xs,
      ),
      decoration: BoxDecoration(
        color: ui.AppColors.surface,
        borderRadius: BorderRadius.circular(ui.AppRadius.lg),
        border: Border.all(color: ui.AppColors.line),
        boxShadow: ui.AppShadows.card,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryStat(
            'Working days',
            '${_summary.totalDays > 0 ? _summary.totalDays : (_summary.presentCount + _summary.absentCount + _summary.leaveCount)}',
            ui.AppColors.ink,
          ),
          _divider(),
          _summaryStat(
            'Present',
            '${_summary.presentCount}',
            ui.AppColors.success,
          ),
          _divider(),
          _summaryStat(
            'Holiday',
            '${_summary.holidayCount}',
            ui.AppColors.warning,
          ),
          _divider(),
          _summaryStat(
            'Absent',
            '${_summary.absentCount}',
            ui.AppColors.error,
          ),
          _divider(),
          _summaryStat(
            'Leave',
            '${_summary.leaveCount}',
            ui.AppColors.info,
          ),
        ],
      ),
    );
  }

  Widget _summaryStat(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: ui.AppType.numeric.copyWith(color: color),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: ui.AppType.micro.copyWith(
            color: ui.AppColors.inkFaint,
            height: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 36,
      color: ui.AppColors.line,
    );
  }

  Widget _buildFilterChips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: ui.AppSpace.gutter),
        itemCount: _filters.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: ui.AppSpace.xs),
        itemBuilder: (context, index) {
          final filter = _filters[index];
          final isSelected = _selectedFilter == filter;

          return Semantics(
            button: true,
            selected: isSelected,
            child: GestureDetector(
              onTap: () => setState(() => _selectedFilter = filter),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: ui.AppSpace.md,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? ui.AppColors.primary
                      : ui.AppColors.surface,
                  borderRadius:
                      BorderRadius.circular(ui.AppRadius.pill),
                  border: Border.all(
                    color: isSelected
                        ? ui.AppColors.primary
                        : ui.AppColors.line,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  filter,
                  style: ui.AppType.meta.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? Colors.white
                        : ui.AppColors.inkMuted,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A translucent pill button in the header — the "Full report" entry point.
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(ui.AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ui.AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ui.AppSpace.sm + 2,
            vertical: ui.AppSpace.xs + 2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(
                icon,
                size: 15,
                color: Colors.white,
                duotoneSecondaryColor: Colors.white70,
                duotoneSecondaryOpacity: 0.5,
              ),
              const SizedBox(width: ui.AppSpace.xxs + 2),
              Text(
                label,
                style: ui.AppType.meta.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
