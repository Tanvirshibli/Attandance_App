import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import '../widgets/gradient_screen_header.dart';
import '../widgets/section_card.dart';
import 'payment_report_screen.dart';
import 'post_payment_screen.dart';

class PaymentHubScreen extends StatelessWidget {
  const PaymentHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(
            child: GradientScreenHeader(
              title: 'Payments',
              subtitle: 'Post loan payments & view payroll',
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                FadeInUp(
                  child: _hubCard(
                    context,
                    icon: Icons.add_card_outlined,
                    title: 'Post Payment',
                    subtitle: 'Submit a loan repayment',
                    color: AppColors.primary,
                    screen: const PostPaymentScreen(),
                  ),
                ),
                const SizedBox(height: 12),
                FadeInUp(
                  delay: const Duration(milliseconds: 100),
                  child: _hubCard(
                    context,
                    icon: Icons.receipt_long_outlined,
                    title: 'Payment Report',
                    subtitle: 'Loan payments & payroll slips',
                    color: AppColors.success,
                    screen: const PaymentReportScreen(),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hubCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Widget screen,
  }) {
    return SectionCard(
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        ),
        borderRadius: BorderRadius.circular(12),
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
    );
  }
}
