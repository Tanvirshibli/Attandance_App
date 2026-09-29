import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';

import '../models/leave_balance.dart';
import '../models/leave_record.dart';
import '../services/auth_service.dart';
import '../services/leave_service.dart';
import '../widgets/filter_chip_row.dart';
import '../widgets/leave_balance_card.dart';
import '../widgets/ui/ui.dart';
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
      backgroundColor: AppColors.canvas,
      // Kept as an extended FAB on purpose: the report section's 100px bottom
      // padding is tuned to clear it. The reload fires on return regardless of
      // whether anything was actually submitted.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ApplyLeaveScreen()),
          );
          _load();
        },
        backgroundColor: AppColors.mLeave,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text(
          'Apply Leave',
          style: AppType.h3.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            const SliverToBoxAdapter(
              child: AppHeader(
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
          padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.md, AppSpace.gutter, AppSpace.xs),
          child: Text(
            'Leave Balance',
            style: AppType.h3.copyWith(color: AppColors.ink),
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
            padding: const EdgeInsets.fromLTRB(AppSpace.gutter, 0, AppSpace.gutter, AppSpace.xs),
            child: AppEmptyState(
              icon: AppIcons.leave,
              title: 'No leave balance data',
              subtitle:
                  'Leave stock will appear once HR configures your account.',
              onRetry: _load,
            ),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(AppSpace.gutter, 0, AppSpace.gutter, AppSpace.xs),
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
    // Returning an empty list hides the whole section, heading included, which
    // shifts the vertical rhythm of everything below. Existing behaviour.
    if (_holidays.isEmpty) return const [];

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.xs),
          child: Text(
            'Upcoming Holidays',
            style: AppType.h3.copyWith(color: AppColors.ink),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(AppSpace.gutter, 0, AppSpace.gutter, AppSpace.xs),
        sliver: SliverList.separated(
          // Hard-capped at 5; existing behaviour.
          itemCount: _holidays.length.clamp(0, 5),
          separatorBuilder: (_, _) => const SizedBox(height: AppSpace.xs),
          itemBuilder: (context, index) {
            final h = _holidays[index];
            return AppCard(
              padding: const EdgeInsets.all(AppSpace.sm + 2),
              child: Row(
                children: [
                  AppIcon(
                    AppIcons.calendar,
                    size: 18,
                    color: AppColors.mLeave,
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          h['holidayName']?.toString() ?? 'Holiday',
                          style: AppType.bodySm.copyWith(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${h['startDate']} → ${h['endDate']}',
                          style: AppType.micro
                              .copyWith(color: AppColors.inkFaint),
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
          padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.xs),
          child: Text(
            'Leave Report',
            style: AppType.h3.copyWith(color: AppColors.ink),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.gutter, 0, AppSpace.gutter, AppSpace.xs),
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
            padding: const EdgeInsets.fromLTRB(AppSpace.gutter, 0, AppSpace.gutter, 100),
            child: AppEmptyState(
              icon: AppIcons.clock,
              title: 'No leave records',
              onRetry: _loadHistoryOnly,
            ),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(AppSpace.gutter, 0, AppSpace.gutter, 100),
          sliver: SliverList.separated(
            itemCount: _records.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = _records[index];
              return FadeInUp(
                delay: Duration(milliseconds: 40 * index),
                child: AppCard(
                  padding: const EdgeInsets.all(AppSpace.sm + 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.leaveTypeName,
                              style: AppType.h3.copyWith(color: AppColors.ink),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpace.xs),
                          AppStatusChip(
                            status: item.status,
                            color: _statusColor(item.status),
                            compact: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        item.dateRangeLabel,
                        style:
                            AppType.micro.copyWith(color: AppColors.inkFaint),
                      ),
                      if (item.duration != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${item.duration} day${item.duration == 1 ? '' : 's'}',
                          style: AppType.micro
                              .copyWith(color: AppColors.inkFaint),
                        ),
                      ],
                      if (item.reason != null && item.reason!.isNotEmpty) ...[
                        const SizedBox(height: AppSpace.xxs),
                        Text(
                          item.reason!,
                          style:
                              AppType.bodySm.copyWith(color: AppColors.ink),
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
