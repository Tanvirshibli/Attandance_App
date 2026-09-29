import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';

import '../models/payment_models.dart';
import '../services/auth_service.dart';
import '../services/payment_service.dart';
import '../widgets/ui/ui.dart';
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
      backgroundColor: AppColors.canvas,
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
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: AppEmptyState(
                    icon: AppIcons.loan,
                    title: 'No active loans',
                    subtitle: 'Approved or ongoing loans will show here.',
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.gutter,
                  AppSpace.md,
                  AppSpace.gutter,
                  AppSpace.xl,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final loan = _loans[index];
                      // Guards divide-by-zero and over-payment; unchanged.
                      final progress = loan.amount <= 0
                          ? 0.0
                          : ((loan.paidAmount ?? 0) / loan.amount)
                              .clamp(0.0, 1.0);
                      return FadeInUp(
                        delay: Duration(milliseconds: 50 * index),
                        child: Padding(
                          padding:
                              const EdgeInsets.only(bottom: AppSpace.sm),
                          child: AppCard(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    LoanDetailScreen(loanId: loan.id),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        loan.label,
                                        style: AppType.h3.copyWith(
                                          color: AppColors.ink,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: AppSpace.xs),
                                    AppStatusChip(
                                      status: loan.status,
                                      compact: true,
                                    ),
                                  ],
                                ),
                                // A null loan type is omitted, not dashed.
                                if (loan.loanType != null) ...[
                                  const SizedBox(height: AppSpace.xs),
                                  Text(
                                    loan.loanType!,
                                    style: AppType.meta.copyWith(
                                      color: AppColors.inkMuted,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                const SizedBox(height: AppSpace.sm),
                                Row(
                                  children: [
                                    Text(
                                      'Remaining ${loan.formattedRemaining}',
                                      style: AppType.h3.copyWith(
                                        color: AppColors.ink,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      'of ${loan.formattedAmount}',
                                      style: AppType.meta.copyWith(
                                        color: AppColors.inkFaint,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpace.xs),
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
