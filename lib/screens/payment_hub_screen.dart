import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../config/theme.dart';
import '../models/payment_models.dart';
import '../services/auth_service.dart';
import '../services/payment_service.dart';
import '../widgets/gradient_screen_header.dart';
import '../widgets/section_card.dart';
import 'compensation_screen.dart';
import 'loan_list_screen.dart';
import 'mess_deposit_screen.dart';
import 'payment_report_screen.dart';
import 'payslip_list_screen.dart';
import 'post_payment_screen.dart';
import 'provident_fund_screen.dart';

class PaymentHubScreen extends StatefulWidget {
  const PaymentHubScreen({super.key});

  @override
  State<PaymentHubScreen> createState() => _PaymentHubScreenState();
}

class _PaymentHubScreenState extends State<PaymentHubScreen> {
  final PaymentService _paymentService = PaymentService();
  final AuthService _authService = AuthService();

  bool _isLoading = true;
  PaymentsHubSummary? _summary;
  final _money = NumberFormat.currency(symbol: '৳', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final profile = await _authService.getCurrentUserProfile();
    final employeeId = profile?.canonicalEmployeeId ?? 0;
    final result = await _paymentService.getHubSummary(employeeId);
    if (!mounted) return;
    setState(() {
      _summary = result.data;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            const SliverToBoxAdapter(
              child: GradientScreenHeader(
                title: 'Payments',
                subtitle: 'Payslips, loans, PF & more',
              ),
            ),
            if (_paymentService.useDemoData)
              SliverToBoxAdapter(child: _demoBanner()),
            if (_isLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else ...[
              if (_summary != null)
                SliverToBoxAdapter(child: _summaryStrip(_summary!)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _hubCard(
                      delay: 0,
                      icon: Icons.receipt_long_rounded,
                      title: 'Payslips',
                      subtitle: 'Monthly salary breakdown',
                      color: AppColors.primary,
                      screen: const PayslipListScreen(),
                    ),
                    _hubCard(
                      delay: 60,
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'My loans',
                      subtitle: 'Active loans & balances',
                      color: AppColors.warning,
                      screen: const LoanListScreen(),
                    ),
                    _hubCard(
                      delay: 120,
                      icon: Icons.history_rounded,
                      title: 'Loan payments',
                      subtitle: 'Repayment history & payroll slips',
                      color: AppColors.info,
                      screen: const PaymentReportScreen(),
                    ),
                    _hubCard(
                      delay: 180,
                      icon: Icons.add_card_outlined,
                      title: 'Post payment',
                      subtitle: 'Submit a loan repayment',
                      color: AppColors.success,
                      screen: const PostPaymentScreen(),
                    ),
                    _hubCard(
                      delay: 240,
                      icon: Icons.savings_outlined,
                      title: 'Provident fund',
                      subtitle: 'PF balance & history',
                      color: const Color(0xFF7C4DFF),
                      screen: const ProvidentFundScreen(),
                    ),
                    _hubCard(
                      delay: 300,
                      icon: Icons.restaurant_outlined,
                      title: 'Mess deposit',
                      subtitle: 'Latest mess contribution',
                      color: AppColors.error,
                      screen: const MessDepositScreen(),
                    ),
                    _hubCard(
                      delay: 360,
                      icon: Icons.badge_outlined,
                      title: 'Compensation',
                      subtitle: 'Salary structure allowances',
                      color: AppColors.accent,
                      screen: const CompensationScreen(),
                    ),
                  ]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _demoBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(Icons.science_outlined, size: 18, color: AppColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Demo data shaped like HRM payroll/loan APIs',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryStrip(PaymentsHubSummary summary) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: FadeInUp(
        child: SectionCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Row(
            children: [
              _summaryCell(
                'Latest net',
                summary.latestNetPay != null
                    ? _money.format(summary.latestNetPay)
                    : '—',
                summary.latestPayslipMonth ?? 'Payslip',
              ),
              _divider(),
              _summaryCell(
                'Loan due',
                summary.openLoanRemaining != null
                    ? _money.format(summary.openLoanRemaining)
                    : '—',
                'Outstanding',
              ),
              _divider(),
              _summaryCell(
                'PF balance',
                summary.pfClosingBalance != null
                    ? _money.format(summary.pfClosingBalance)
                    : '—',
                'Closing',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 44,
        color: AppColors.divider,
      );

  Widget _summaryCell(String label, String value, String hint) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            hint,
            style: GoogleFonts.poppins(
              fontSize: 9,
              color: AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hubCard({
    required int delay,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Widget screen,
  }) {
    return FadeInUp(
      delay: Duration(milliseconds: delay),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SectionCard(
          padding: EdgeInsets.zero,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => screen),
            ),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
