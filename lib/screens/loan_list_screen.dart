import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import '../models/payment_models.dart';
import '../services/auth_service.dart';
import '../services/payment_service.dart';
import '../widgets/api_empty_state.dart';
import '../widgets/gradient_screen_header.dart';
import '../widgets/section_card.dart';
import 'loan_detail_screen.dart';

class LoanListScreen extends StatefulWidget {
  const LoanListScreen({super.key});

  @override
  State<LoanListScreen> createState() => _LoanListScreenState();
}

class _LoanListScreenState extends State<LoanListScreen> {
  final PaymentService _paymentService = PaymentService();
  final AuthService _authService = AuthService();

  bool _isLoading = true;
  List<EmployeeLoan> _loans = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final profile = await _authService.getCurrentUserProfile();
    final result = await _paymentService.getEmployeeLoans(
      profile?.canonicalEmployeeId ?? 0,
    );
    if (!mounted) return;
    setState(() {
      _loans = result.data ?? const [];
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
                title: 'My loans',
                subtitle: 'Approved & ongoing loans',
              ),
            ),
            if (_isLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_loans.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: ApiEmptyState(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'No active loans',
                    subtitle: 'Approved or ongoing loans will show here.',
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final loan = _loans[index];
                      final progress = loan.amount <= 0
                          ? 0.0
                          : ((loan.paidAmount ?? 0) / loan.amount)
                              .clamp(0.0, 1.0);
                      return FadeInUp(
                        delay: Duration(milliseconds: 50 * index),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SectionCard(
                            child: InkWell(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      LoanDetailScreen(loanId: loan.id),
                                ),
                              ),
                              borderRadius: BorderRadius.circular(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          loan.label,
                                          style: GoogleFonts.poppins(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.warning
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          loan.status,
                                          style: GoogleFonts.poppins(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.warning,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (loan.loanType != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      loan.loanType!,
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Text(
                                        'Remaining ${loan.formattedRemaining}',
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        'of ${loan.formattedAmount}',
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: AppColors.textHint,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      minHeight: 8,
                                      backgroundColor: AppColors.warning
                                          .withValues(alpha: 0.15),
                                      color: AppColors.warning,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: _loans.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
