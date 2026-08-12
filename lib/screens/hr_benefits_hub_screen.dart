import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
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

class HrBenefitsHubScreen extends StatelessWidget {
  const HrBenefitsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final useDemoData = PaymentService().useDemoData;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(
            child: GradientScreenHeader(
              title: 'HR Benefits',
              subtitle: 'Payslips, loans, PF and related HR records',
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (useDemoData) ...[
                  _demoBanner(),
                  const SizedBox(height: 12),
                ],
                _hubCard(
                  context,
                  delay: 0,
                  icon: Icons.receipt_long_rounded,
                  title: 'Payslips',
                  subtitle: 'Monthly salary breakdown',
                  color: AppColors.primary,
                  screen: const PayslipListScreen(),
                ),
                _hubCard(
                  context,
                  delay: 40,
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'My loans',
                  subtitle: 'Active loans & balances',
                  color: AppColors.warning,
                  screen: const LoanListScreen(),
                ),
                _hubCard(
                  context,
                  delay: 80,
                  icon: Icons.history_rounded,
                  title: 'Loan payments',
                  subtitle: 'Repayment history & payroll slips',
                  color: AppColors.info,
                  screen: const PaymentReportScreen(),
                ),
                _hubCard(
                  context,
                  delay: 120,
                  icon: Icons.add_card_outlined,
                  title: 'Post payment',
                  subtitle: 'Submit a loan repayment',
                  color: AppColors.success,
                  screen: const PostPaymentScreen(),
                ),
                _hubCard(
                  context,
                  delay: 160,
                  icon: Icons.savings_outlined,
                  title: 'Provident fund',
                  subtitle: 'PF balance & history',
                  color: const Color(0xFF7C4DFF),
                  screen: const ProvidentFundScreen(),
                ),
                _hubCard(
                  context,
                  delay: 200,
                  icon: Icons.restaurant_outlined,
                  title: 'Mess deposit',
                  subtitle: 'Latest mess contribution',
                  color: AppColors.error,
                  screen: const MessDepositScreen(),
                ),
                _hubCard(
                  context,
                  delay: 240,
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
      ),
    );
  }

  Widget _demoBanner() {
    return Container(
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
              'HR benefits use demo payroll/loan data',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hubCard(
    BuildContext context, {
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
