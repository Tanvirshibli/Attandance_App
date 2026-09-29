import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';

import '../services/payment_service.dart';
import '../widgets/ui/ui.dart';
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
      backgroundColor: AppColors.canvas,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(
            child: AppHeader(
              title: 'HR Benefits',
              subtitle: 'Payslips, loans, PF and related HR records',
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.xs, AppSpace.gutter, AppSpace.xl),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (useDemoData) ...[
                  _demoBanner(),
                  const SizedBox(height: 12),
                ],
                _hubCard(
                  context,
                  delay: 0,
                  icon: AppIcons.invoice,
                  title: 'Payslips',
                  subtitle: 'Monthly salary breakdown',
                  color: AppColors.mHr,
                  screen: const PayslipListScreen(),
                ),
                _hubCard(
                  context,
                  delay: 40,
                  icon: AppIcons.loan,
                  title: 'My loans',
                  subtitle: 'Active loans & balances',
                  color: AppColors.mPayments,
                  screen: const LoanListScreen(),
                ),
                _hubCard(
                  context,
                  delay: 80,
                  icon: AppIcons.clock,
                  title: 'Loan payments',
                  subtitle: 'Repayment history & payroll slips',
                  color: AppColors.mVehicles,
                  screen: const PaymentReportScreen(),
                ),
                _hubCard(
                  context,
                  delay: 120,
                  icon: AppIcons.plus,
                  title: 'Post payment',
                  subtitle: 'Submit a loan repayment',
                  color: AppColors.mSales,
                  screen: const PostPaymentScreen(),
                ),
                _hubCard(
                  context,
                  delay: 160,
                  icon: AppIcons.piggy,
                  title: 'Provident fund',
                  subtitle: 'PF balance & history',
                  color: const Color(0xFF7C4DFF),
                  screen: const ProvidentFundScreen(),
                ),
                _hubCard(
                  context,
                  delay: 200,
                  icon: AppIcons.fork,
                  title: 'Mess deposit',
                  subtitle: 'Latest mess contribution',
                  color: AppColors.mLeave,
                  screen: const MessDepositScreen(),
                ),
                _hubCard(
                  context,
                  delay: 240,
                  icon: AppIcons.badge,
                  title: 'Compensation',
                  subtitle: 'Salary structure allowances',
                  color: AppColors.mFarms,
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
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          AppIcon(
            AppIcons.warning,
            size: 18,
            color: AppColors.warning,
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              'HR benefits use demo payroll/loan data',
              style: AppType.meta.copyWith(
                color: AppColors.ink,
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
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        // The untyped `push(MaterialPageRoute(builder: (_) => screen))` is
        // deliberate and unchanged: the screen is pre-built and the result is
        // discarded.
        child: AppCard(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => screen),
          ),
          padding: const EdgeInsets.all(AppSpace.sm + 2),
          child: Row(
            children: [
              AppIconTile(
                icon: icon,
                color: color,
                semanticLabel: title,
              ),
              const SizedBox(width: AppSpace.sm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppType.h3.copyWith(color: AppColors.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: AppType.meta.copyWith(color: AppColors.inkMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              AppIcon(
                AppIcons.chevron,
                size: 18,
                color: AppColors.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
