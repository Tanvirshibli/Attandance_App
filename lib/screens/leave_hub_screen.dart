import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import '../models/leave_balance.dart';
import '../services/auth_service.dart';
import '../services/leave_service.dart';
import '../widgets/api_empty_state.dart';
import '../widgets/gradient_screen_header.dart';
import '../widgets/section_card.dart';
import 'apply_leave_screen.dart';
import 'leave_balance_screen.dart';
import 'leave_report_screen.dart';

class LeaveHubScreen extends StatefulWidget {
  const LeaveHubScreen({super.key});

  @override
  State<LeaveHubScreen> createState() => _LeaveHubScreenState();
}

class _LeaveHubScreenState extends State<LeaveHubScreen> {
  final LeaveService _leaveService = LeaveService();
  final AuthService _authService = AuthService();

  List<LeaveBalance> _balances = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final profile = await _authService.getCurrentUserProfile();
    final employeeId = profile?.canonicalEmployeeId;
    if (employeeId == null) {
      if (!mounted) return;
      setState(() {
        _balances = const [];
        _isLoading = false;
      });
      return;
    }

    final result = await _leaveService.getBalances(employeeId);
    if (!mounted) return;
    setState(() {
      _balances = result.data ?? const [];
      _isLoading = false;
    });
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
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(
            child: GradientScreenHeader(
              title: 'Leave',
              subtitle: 'Balance, history & applications',
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _navCard(
                      context,
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Balance',
                      color: AppColors.info,
                      screen: const LeaveBalanceScreen(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _navCard(
                      context,
                      icon: Icons.history_rounded,
                      label: 'Report',
                      color: AppColors.success,
                      screen: const LeaveReportScreen(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Text(
                'Quick Balance',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
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
          else if (_balances.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: ApiEmptyState(
                  icon: Icons.beach_access_outlined,
                  title: 'No leave balance data',
                  subtitle: 'Leave stock will appear once HR configures your account.',
                  onRetry: _load,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
              sliver: SliverList.separated(
                itemCount: _balances.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = _balances[index];
                  return FadeInUp(
                    delay: Duration(milliseconds: 60 * index),
                    child: SectionCard(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.leaveTypeName,
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Earned ${item.earned.toStringAsFixed(1)} · Used ${item.used.toStringAsFixed(1)}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            item.balance.toStringAsFixed(1),
                            style: GoogleFonts.poppins(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _navCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required Widget screen,
  }) {
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
