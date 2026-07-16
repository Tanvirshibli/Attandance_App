import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../config/theme.dart';
import '../models/payment_models.dart';
import '../services/auth_service.dart';
import '../services/payment_service.dart';
import '../widgets/api_empty_state.dart';
import '../widgets/gradient_screen_header.dart';
import '../widgets/section_card.dart';

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
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: ApiEmptyState(
                    icon: Icons.savings_outlined,
                    title: 'No PF record',
                    subtitle: 'Provident fund data will appear when available.',
                  ),
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: FadeInUp(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Closing balance',
                            style: GoogleFonts.poppins(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            _current!.formattedBalance,
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (_current!.month != null)
                            Text(
                              'Month ${_current!.month}',
                              style: GoogleFonts.poppins(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                sliver: SliverToBoxAdapter(
                  child: FadeInUp(
                    delay: const Duration(milliseconds: 60),
                    child: SectionCard(
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
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = _history[index];
                        return FadeInUp(
                          delay: Duration(milliseconds: 40 * index),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SectionCard(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.month ?? 'PF #${item.id}',
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    item.formattedBalance,
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
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

  Widget _row(String label, double? value) {
    if (value == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            _money.format(value),
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
