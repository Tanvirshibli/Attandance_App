import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';

import '../models/payment_models.dart';
import '../services/auth_service.dart';
import '../services/payment_service.dart';
import '../widgets/ui/ui.dart';

class CompensationScreen extends StatefulWidget {
  const CompensationScreen({super.key});

  @override
  State<CompensationScreen> createState() => _CompensationScreenState();
}

class _CompensationScreenState extends State<CompensationScreen> {
  final PaymentService _paymentService = PaymentService();
  final AuthService _authService = AuthService();

  bool _isLoading = true;
  CompensationFacility? _facility;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final profile = await _authService.getCurrentUserProfile();
    final result = await _paymentService.getCompensation(
      profile?.canonicalEmployeeId ?? 0,
    );
    if (!mounted) return;
    setState(() {
      _facility = result.data;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = _facility;
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
                title: 'Compensation',
                subtitle: 'Salary structure & allowances',
              ),
            ),
            if (_isLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (f == null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(AppSpace.lg),
                  child: AppEmptyState(
                    icon: AppIcons.badge,
                    title: 'No facility record',
                    subtitle: 'Employee compensation structure not found.',
                  ),
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.md, AppSpace.gutter, AppSpace.xs),
                  child: FadeInUp(
                    child: AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            f.designationName ?? 'Employee',
                            style: AppType.h2
                                .copyWith(color: AppColors.ink),
                          ),
                          const SizedBox(height: AppSpace.xxs),
                          Text(
                            [
                              if (f.departmentName != null)
                                f.departmentName!,
                              if (f.sectorName != null) f.sectorName!,
                            ].join(' · '),
                            style:
                                AppType.meta.copyWith(color: AppColors.inkMuted),
                          ),
                          if (f.sGross != null) ...[
                            const SizedBox(height: AppSpace.md),
                            Text(
                              'Gross ${f.money(f.sGross)}',
                              style: AppType.display
                                  .copyWith(color: AppColors.mPayments),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.xs, AppSpace.gutter, AppSpace.xl),
                sliver: SliverToBoxAdapter(
                  child: FadeInUp(
                    delay: const Duration(milliseconds: 80),
                    child: AppCard(
                      child: Column(
                        children: [
                          _row('Basic', f.money(f.basics)),
                          _row('House', f.money(f.houses)),
                          _row('Medical', f.money(f.medicals)),
                          _row('Food', f.money(f.foods)),
                          _row('Mobile bill', f.money(f.mobileBill)),
                          _row('Mess', f.money(f.mess)),
                          _row('Quarter', f.money(f.quarter)),
                          _row('Service bill', f.money(f.serviceBill)),
                          _row('Loan (facility)', f.money(f.loanF)),
                          _row('Tax', f.money(f.tax)),
                          _row('Payment method', f.paymentMethod ?? '—'),
                          if (f.jDate != null) _row('Join date', f.jDate!),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppType.bodySm.copyWith(color: AppColors.inkMuted),
            ),
          ),
          Text(
            value,
            style: AppType.bodySm
                .copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
