import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import '../models/leave_balance.dart';
import '../models/leave_record.dart';
import '../services/auth_service.dart';
import '../services/leave_service.dart';
import '../widgets/api_empty_state.dart';
import '../widgets/filter_chip_row.dart';
import '../widgets/gradient_screen_header.dart';
import '../widgets/leave_balance_card.dart';
import '../widgets/section_card.dart';
import 'apply_leave_screen.dart';

class LeaveHubScreen extends StatefulWidget {
  const LeaveHubScreen({super.key});

  @override
  State<LeaveHubScreen> createState() => _LeaveHubScreenState();
}

class _LeaveHubScreenState extends State<LeaveHubScreen> {
  final LeaveService _leaveService = LeaveService();
  final AuthService _authService = AuthService();

  List<LeaveBalance> _balances = const [];
  List<LeaveRecord> _records = const [];
  List<Map<String, dynamic>> _holidays = const [];
  bool _isLoadingBalances = true;
  bool _isLoadingHistory = true;
  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'Pending', 'Approved', 'Rejected'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoadingBalances = true;
      _isLoadingHistory = true;
    });

    final profile = await _authService.getCurrentUserProfile();
    final employeeId = profile?.canonicalEmployeeId;
    if (employeeId == null) {
      if (!mounted) return;
      setState(() {
        _balances = const [];
        _records = const [];
        _holidays = const [];
        _isLoadingBalances = false;
        _isLoadingHistory = false;
      });
      return;
    }

    final balancesResult = await _leaveService.getBalances(employeeId);
    final holidaysResult = await _leaveService.getHolidays();
    final historyResult = await _leaveService.getLeaveHistory(
      employeeId: employeeId,
      status: _selectedFilter,
    );

    if (!mounted) return;
    setState(() {
      _balances = balancesResult.data ?? const [];
      _holidays = holidaysResult.data ?? const [];
      _records = historyResult.data ?? const [];
      _isLoadingBalances = false;
      _isLoadingHistory = false;
    });
  }

  Future<void> _loadHistoryOnly() async {
    setState(() => _isLoadingHistory = true);

    final profile = await _authService.getCurrentUserProfile();
    final employeeId = profile?.canonicalEmployeeId;
    if (employeeId == null) {
      if (!mounted) return;
      setState(() {
        _records = const [];
        _isLoadingHistory = false;
      });
      return;
    }

    final historyResult = await _leaveService.getLeaveHistory(
      employeeId: employeeId,
      status: _selectedFilter,
    );

    if (!mounted) return;
    setState(() {
      _records = historyResult.data ?? const [];
      _isLoadingHistory = false;
    });
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return AppColors.success;
      case 'rejected':
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ApplyLeaveScreen()),
          );
          _load();
        },
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text(
          'Apply Leave',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            const SliverToBoxAdapter(
              child: GradientScreenHeader(
                title: 'Leave',
                subtitle: 'Balance & leave history',
              ),
            ),
            ..._buildBalanceSection(context),
            ..._buildHolidaysSection(),
            ..._buildReportSection(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBalanceSection(BuildContext context) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
          child: Text(
            'Leave Balance',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ),
      if (_isLoadingBalances)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          ),
        )
      else if (_balances.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: ApiEmptyState(
              icon: Icons.beach_access_outlined,
              title: 'No leave balance data',
              subtitle:
                  'Leave stock will appear once HR configures your account.',
              onRetry: _load,
            ),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          sliver: SliverList.separated(
            itemCount: _balances.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              return FadeInUp(
                delay: Duration(milliseconds: 40 * index),
                child: LeaveBalanceCard(balance: _balances[index]),
              );
            },
          ),
        ),
    ];
  }

  List<Widget> _buildHolidaysSection() {
    if (_holidays.isEmpty) return const [];

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
          child: Text(
            'Upcoming Holidays',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
        sliver: SliverList.separated(
          itemCount: _holidays.length.clamp(0, 5),
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final h = _holidays[index];
            return SectionCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.event_outlined, color: AppColors.warning, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          h['holidayName']?.toString() ?? 'Holiday',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          '${h['startDate']} → ${h['endDate']}',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ];
  }

  List<Widget> _buildReportSection() {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
          child: Text(
            'Leave Report',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          child: FilterChipRow(
            options: _filters,
            selected: _selectedFilter,
            onSelected: (v) {
              setState(() => _selectedFilter = v);
              _loadHistoryOnly();
            },
          ),
        ),
      ),
      if (_isLoadingHistory)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          ),
        )
      else if (_records.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            child: ApiEmptyState(
              icon: Icons.history_rounded,
              title: 'No leave records',
              onRetry: _loadHistoryOnly,
            ),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          sliver: SliverList.separated(
            itemCount: _records.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = _records[index];
              return FadeInUp(
                delay: Duration(milliseconds: 40 * index),
                child: SectionCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.leaveTypeName,
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _statusColor(item.status)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              item.status,
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _statusColor(item.status),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.dateRangeLabel,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (item.duration != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${item.duration} day${item.duration == 1 ? '' : 's'}',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      if (item.reason != null && item.reason!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.reason!,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
    ];
  }
}
