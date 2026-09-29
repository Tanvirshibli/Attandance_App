import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../widgets/ui/ui.dart' as ui;
import '../models/attendance_request_record.dart';
import '../models/attendance_summary.dart';
import '../services/attendance_report_service.dart';
import '../services/attendance_request_service.dart';
import '../services/auth_service.dart';
import '../widgets/attendance_tile.dart';
import '../widgets/date_range_field.dart';
import '../widgets/filter_chip_row.dart';

class AttendanceReportScreen extends StatefulWidget {
  const AttendanceReportScreen({super.key});

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  final AttendanceRequestService _attendanceService = AttendanceRequestService();
  final AttendanceReportService _reportService = AttendanceReportService();
  final AuthService _authService = AuthService();

  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'Requested', 'Approved', 'Rejected'];
  late DateTime _from;
  late DateTime _to;

  List<AttendanceRequestRecord> _records = const [];
  AttendanceSummary? _summary;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = now;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final profile = await _authService.getCurrentUserProfile();
    final employeeId = profile?.canonicalEmployeeId;

    String? status;
    if (_selectedFilter != 'All') {
      status = _selectedFilter.toLowerCase();
    }

    final records = await _attendanceService.getAttendanceRecords(
      employeeId: employeeId,
      status: status,
      from: _from,
      to: _to,
    );

    AttendanceSummary? summary;
    if (employeeId != null && employeeId > 0) {
      final summaryResult = await _reportService.getSummary(
        employeeId: employeeId,
        from: _from,
        to: _to,
      );
      if (summaryResult.success && summaryResult.data != null) {
        summary = summaryResult.data;
      }
    }

    summary ??= AttendanceSummary.fromRecords(
      approved: records.where((r) => r.status.toLowerCase() == 'approved').length,
      requested: records.where((r) => r.status.toLowerCase() == 'requested').length,
      rejected: records.where((r) => r.status.toLowerCase() == 'rejected').length,
    );

    // HRM rows can mark punched days absent (mobile punches live in
    // ZKTeco) — move days with a real punch back to present.
    summary = summary.reconciledWithPunchDays(_punchDaysFrom(records));

    if (!mounted) return;
    setState(() {
      _records = records;
      _summary = summary;
      _isLoading = false;
      _error = records.isEmpty ? 'No attendance records for this period.' : null;
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

  List<Map<String, dynamic>> get _filteredRecords {
    return _records.map((item) => item.toTileRecord()).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ui.AppColors.canvas,
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: ui.AppColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: ui.AppHeader(
                title: 'Attendance report',
                subtitle:
                    '${DateFormat('dd MMM').format(_from)} – ${DateFormat('dd MMM yyyy').format(_to)}',
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  ui.AppSpace.gutter,
                  ui.AppSpace.sm,
                  ui.AppSpace.gutter,
                  ui.AppSpace.xs,
                ),
                child: DateRangeField(
                  from: _from,
                  to: _to,
                  onChanged: (from, to) {
                    setState(() {
                      _from = from;
                      _to = to;
                    });
                    _loadData();
                  },
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ui.AppSpace.gutter,
                ),
                child: FilterChipRow(
                  options: _filters,
                  selected: _selectedFilter,
                  onSelected: (value) {
                    setState(() => _selectedFilter = value);
                    _loadData();
                  },
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  ui.AppSpace.gutter,
                  ui.AppSpace.md,
                  ui.AppSpace.gutter,
                  0,
                ),
                child: _buildSummaryRow(_summary ?? const AttendanceSummary()),
              ),
            ),
            if (_records.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ui.AppSpace.gutter,
                    ui.AppSpace.md,
                    ui.AppSpace.gutter,
                    ui.AppSpace.xs,
                  ),
                  child: ui.AppSectionTitle(
                    title: 'Punch timeline',
                    subtitle: '${_records.length} punches',
                    accent: ui.AppColors.mAttendance,
                  ),
                ),
              ),
            if (_records.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ui.AppSpace.gutter,
                ),
                sliver: SliverList.separated(
                  itemCount: _records.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: ui.AppSpace.xs),
                  itemBuilder: (context, index) {
                    return _buildPunchCard(_records[index]);
                  },
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  ui.AppSpace.gutter,
                  ui.AppSpace.md,
                  ui.AppSpace.gutter,
                  ui.AppSpace.xs,
                ),
                child: ui.AppSectionTitle(
                  title: 'Daily summary',
                  subtitle: _isLoading ? 'Loading' : '${_filteredRecords.length} days',
                  accent: ui.AppColors.mSales,
                ),
              ),
            ),
            if (_isLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(ui.AppSpace.xl),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_filteredRecords.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(ui.AppSpace.lg),
                  child: ui.AppEmptyState(
                    icon: ui.AppIcons.calendar,
                    title: 'No records found',
                    subtitle: _error ?? 'Nothing recorded in this period.',
                    onRetry: _loadData,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  ui.AppSpace.gutter,
                  ui.AppSpace.xs,
                  ui.AppSpace.gutter,
                  ui.AppSpace.fabClearance,
                ),
                sliver: SliverList.separated(
                  itemCount: _filteredRecords.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: ui.AppSpace.xs),
                  itemBuilder: (context, index) {
                    return AttendanceTile(record: _filteredRecords[index]);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: ui.AppSpace.sm + 2,
          horizontal: ui.AppSpace.xxs,
        ),
        decoration: BoxDecoration(
          color: ui.AppColors.surface,
          borderRadius: BorderRadius.circular(ui.AppRadius.lg),
          border: Border.all(color: ui.AppColors.line),
          boxShadow: ui.AppShadows.card,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$value',
                style: ui.AppType.numeric.copyWith(color: color),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ui.AppType.micro
                  .copyWith(color: ui.AppColors.inkFaint),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(AttendanceSummary summary) {
    return Row(
      children: [
        _summaryCard('Present', summary.presentCount, ui.AppColors.success),
        const SizedBox(width: ui.AppSpace.xs),
        _summaryCard('Leave', summary.leaveCount, ui.AppColors.info),
        const SizedBox(width: ui.AppSpace.xs),
        _summaryCard('Absent', summary.absentCount, ui.AppColors.error),
        const SizedBox(width: ui.AppSpace.xs),
        _summaryCard('Holiday', summary.holidayCount, ui.AppColors.warning),
      ],
    );
  }

  Widget _buildPunchCard(AttendanceRequestRecord record) {
    final hasGeo = record.latitude != null && record.longitude != null;
    return ui.AppCard(
      padding: const EdgeInsets.all(ui.AppSpace.sm + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  record.attDate,
                  style: ui.AppType.h3.copyWith(color: ui.AppColors.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (record.faceVerified == true)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ui.AppSpace.xs,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: ui.AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(ui.AppRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ui.AppIcon(
                        ui.AppIcons.shield,
                        size: 12,
                        color: ui.AppColors.success,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Face',
                        style: ui.AppType.micro.copyWith(
                          color: ui.AppColors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: ui.AppSpace.xs),
          Row(
            children: [
              ui.AppIcon(
                ui.AppIcons.clock,
                size: 13,
                color: ui.AppColors.inkFaint,
              ),
              const SizedBox(width: ui.AppSpace.xxs + 2),
              Expanded(
                child: Text(
                  'In ${record.checkInText}  ·  Out ${record.checkOutText}',
                  style: ui.AppType.meta
                      .copyWith(color: ui.AppColors.inkMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: ui.AppSpace.xxs + 2),
          ui.AppStatusChip(status: record.status, compact: true),
          if (hasGeo || (record.address?.isNotEmpty ?? false)) ...[
            const SizedBox(height: ui.AppSpace.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ui.AppIcon(
                  ui.AppIcons.pin,
                  size: 13,
                  color: ui.AppColors.mGeo,
                ),
                const SizedBox(width: ui.AppSpace.xxs + 2),
                Expanded(
                  child: Text(
                    record.address?.isNotEmpty == true
                        ? record.address!
                        : '${record.latitude!.toStringAsFixed(5)}, ${record.longitude!.toStringAsFixed(5)}',
                    style: ui.AppType.micro
                        .copyWith(color: ui.AppColors.inkFaint),
                    maxLines: 2,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
