import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';

import '../models/payment_models.dart';
import '../services/auth_service.dart';
import '../services/payment_service.dart';
import '../widgets/ui/ui.dart';

class MessDepositScreen extends StatefulWidget {
  const MessDepositScreen({super.key});

  @override
  State<MessDepositScreen> createState() => _MessDepositScreenState();
}

class _MessDepositScreenState extends State<MessDepositScreen> {
  final PaymentService _paymentService = PaymentService();
  final AuthService _authService = AuthService();

  bool _isLoading = true;
  MessDepositRecord? _record;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final profile = await _authService.getCurrentUserProfile();
    final result = await _paymentService.getMessDeposit(
      profile?.canonicalEmployeeId ?? 0,
    );
    if (!mounted) return;
    setState(() {
      _record = result.data;
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
                title: 'Mess deposit',
                subtitle: 'Latest approved contribution',
              ),
            ),
            if (_isLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_record == null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: AppEmptyState(
                    icon: AppIcons.fork,
                    title: 'No mess deposit',
                    subtitle: 'Approved mess deposits will appear here.',
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
                sliver: SliverToBoxAdapter(
                  child: FadeInUp(
                    child: AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _record!.formattedAmount,
                            style: AppType.display
                                .copyWith(color: AppColors.mPayments),
                          ),
                          const SizedBox(height: AppSpace.xxs),
                          Text(
                            'This transaction',
                            style: AppType.meta
                                .copyWith(color: AppColors.inkMuted),
                          ),
                          const SizedBox(height: AppSpace.md),
                          // Null values show an em-dash here, except the Note
                          // row, which is omitted entirely. Both behaviours are
                          // deliberate and preserved.
                          _row('Deposit ID', _record!.messDepositId ?? '—'),
                          _row('Total deposited', _record!.formattedTotal),
                          _row('Type', _record!.tType ?? '—'),
                          _row('Date', _record!.tDate ?? '—'),
                          _row('Status', _record!.status ?? '—'),
                          _row('Department', _record!.department ?? '—'),
                          if (_record!.note != null)
                            _row('Note', _record!.note!),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: AppType.bodySm.copyWith(color: AppColors.inkMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppType.bodySm
                  .copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
