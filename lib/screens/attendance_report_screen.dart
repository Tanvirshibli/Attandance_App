import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../config/theme.dart';
import '../models/attendance_request_record.dart';
import '../models/attendance_summary.dart';
import '../services/attendance_report_service.dart';
import '../services/attendance_request_service.dart';
import '../services/auth_service.dart';
import '../widgets/api_empty_state.dart';
import '../widgets/attendance_tile.dart';
import '../widgets/date_range_field.dart';
import '../widgets/filter_chip_row.dart';
import '../widgets/gradient_screen_header.dart';
import '../widgets/section_card.dart';

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

    if (!mounted) return;
    setState(() {
      _records = records;
      _summary = summary;
      _isLoading = false;
      _error = records.isEmpty ? 'No attendance records for this period.' : null;
    });
  }

  List<Map<String, dynamic>> get _filteredRecords {
    return _records.map((item) => item.toTileRecord()).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: GradientScreenHeader(
                title: 'Attendance Report',
                subtitle:
                    '${DateFormat('dd MMM').format(_from)} - ${DateFormat('dd MMM yyyy').format(_to)}',
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
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
                padding: const EdgeInsets.symmetric(horizontal: 20),
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: FadeInUp(
                  child: _buildSummaryRow(_summary ?? const AttendanceSummary()),
                ),
              ),
            ),
            if (_isLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_filteredRecords.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: ApiEmptyState(
                    icon: Icons.event_busy_outlined,
                    title: 'No records found',
                    subtitle: _error,
                    onRetry: _loadData,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                sliver: SliverList.separated(
                  itemCount: _filteredRecords.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    return FadeInUp(
                      delay: Duration(milliseconds: 50 * (index % 6)),
                      child: AttendanceTile(record: _filteredRecords[index]),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(AttendanceSummary summary) {
    return Row(
      children: [
        _summaryCard('Present', summary.presentCount, AppColors.success),
        const SizedBox(width: 8),
        _summaryCard('Leave', summary.leaveCount, AppColors.info),
        const SizedBox(width: 8),
        _summaryCard('Absent', summary.absentCount, AppColors.error),
        const SizedBox(width: 8),
        _summaryCard('Holiday', summary.holidayCount, AppColors.warning),
      ],
    );
  }

  Widget _summaryCard(String label, int value, Color color) {
    return Expanded(
      child: SectionCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Text(
              '$value',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
