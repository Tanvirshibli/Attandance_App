import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/payment_models.dart';
import '../services/auth_service.dart';
import '../services/payment_service.dart';
import '../widgets/ui/ui.dart';

class ProvidentFundScreen extends StatefulWidget {
  const ProvidentFundScreen({super.key});

  @override
  State<ProvidentFundScreen> createState() => _ProvidentFundScreenState();
}

class _ProvidentFundScreenState extends State<ProvidentFundScreen> {
  final PaymentService _paymentService = PaymentService();
  final AuthService _authService = AuthService();
  final _money = NumberFormat.currency(symbol: '৳', decimalDigits: 0);

  bool _isLoading = true;
  ProvidentFundRecord? _current;
  List<ProvidentFundRecord> _history = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final profile = await _authService.getCurrentUserProfile();
    final id = profile?.canonicalEmployeeId ?? 0;
    final current = await _paymentService.getProvidentFund(id);
    final history = await _paymentService.getProvidentFundHistory(id);
    if (!mounted) return;
    setState(() {
      _current = current.data;
      _history = history.data ?? const [];
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
                title: 'Provident fund',
                subtitle: 'Balance & monthly ledger',
              ),
            ),
            if (_isLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_current == null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(AppSpace.lg),
                  child: AppEmptyState(
                    icon: AppIcons.piggy,
                    title: 'No PF record',
                    subtitle: 'Provident fund data will appear when available.',
                  ),
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.md, AppSpace.gutter, AppSpace.xs),
                  child: FadeInUp(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Closing balance',
                            style: AppType.meta.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                          Text(
                            _current!.formattedBalance,
                            style: AppType.display
                                .copyWith(color: Colors.white),
                          ),
                          if (_current!.month != null)
                            Text(
                              'Month ${_current!.month}',
                              style: AppType.meta
                                  .copyWith(color: Colors.white70),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.xs, AppSpace.gutter, AppSpace.md),
                sliver: SliverToBoxAdapter(
                  child: FadeInUp(
                    delay: const Duration(milliseconds: 60),
                    child: AppCard(
                      child: Column(
                        children: [
                          _row('Opening', _current!.openingBalance),
                          _row('Monthly PF', _current!.monthlyPfAmount),
                          _row('PF total', _current!.pfAmountTotal),
                          _row('Interest total', _current!.pfInterestTotal),
                          _row(
                            'With profit',
                            _current!.closingBalanceWithProfit,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_history.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.gutter, 0, AppSpace.gutter, AppSpace.xl),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = _history[index];
                        return FadeInUp(
                          delay: Duration(milliseconds: 40 * index),
                          child: Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpace.xs,
                            ),
                            child: AppCard(
                              padding: const EdgeInsets.all(
                                AppSpace.sm + 2,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.month ?? 'PF #${item.id}',
                                      style: AppType.h3.copyWith(
                                        color: AppColors.ink,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpace.xs),
                                  Text(
                                    item.formattedBalance,
                                    style: AppType.h3.copyWith(
                                      color: AppColors.mHr,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: _history.length,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Unlike the other record screens, a null value is dropped from the list
  /// entirely rather than rendered as a dash. Preserved deliberately.
  Widget _row(String label, double? value) {
    if (value == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppType.bodySm.copyWith(color: AppColors.inkMuted),
            ),
          ),
          Text(
            _money.format(value),
            style: AppType.bodySm
                .copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
