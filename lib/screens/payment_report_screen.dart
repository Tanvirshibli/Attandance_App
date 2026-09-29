import 'package:flutter/material.dart';

import '../models/payment_models.dart';
import '../services/auth_service.dart';
import '../services/payment_service.dart';
import '../widgets/ui/ui.dart';

class PaymentReportScreen extends StatefulWidget {
  const PaymentReportScreen({super.key});

  @override
  State<PaymentReportScreen> createState() => _PaymentReportScreenState();
}

class _PaymentReportScreenState extends State<PaymentReportScreen>
    with SingleTickerProviderStateMixin {
  final PaymentService _paymentService = PaymentService();
  final AuthService _authService = AuthService();
  late TabController _tabController;

  List<LoanPayment> _loanPayments = const [];
  List<PayrollRecord> _payrolls = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final profile = await _authService.getCurrentUserProfile();
    final employeeId = profile?.canonicalEmployeeId ?? 0;

    final payments = await _paymentService.getLoanPayments(employeeId);
    final payrolls = await _paymentService.getPayrollRecords(
      employeeId: employeeId,
    );

    if (!mounted) return;
    setState(() {
      _loanPayments = payments.data ?? const [];
      _payrolls = payrolls.data ?? const [];
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Column(
        children: [
          AppHeader(
            title: 'Payment Report',
            trailing: IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            ),
          ),
          Material(
            color: AppColors.surface,
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.inkMuted,
              indicatorColor: AppColors.primary,
              labelStyle: AppType.h3.copyWith(fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Loan Payments'),
                Tab(text: 'Payroll'),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _loanPaymentsTab(),
                      _payrollTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _loanPaymentsTab() {
    if (_loanPayments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: AppEmptyState(
          icon: AppIcons.payments,
          title: 'No loan payments',
          onRetry: _load,
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpace.lg),
      itemCount: _loanPayments.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
      itemBuilder: (context, index) {
        final item = _loanPayments[index];
        return AppCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '৳${item.amount.toStringAsFixed(2)}',
                      style: AppType.h2.copyWith(color: AppColors.ink),
                    ),
                    Text(
                      item.formattedDate,
                      style:
                          AppType.meta.copyWith(color: AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
              // Colour is pinned to the module accent, not derived from the
              // status string — the original showed every loan-payment status
              // in the same colour.
              AppStatusChip(
                status: item.status,
                color: AppColors.mVehicles,
                compact: true,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _payrollTab() {
    if (_payrolls.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: AppEmptyState(
          icon: AppIcons.invoice,
          title: 'No payroll records',
          subtitle: 'Payroll for this month is not available yet.',
          onRetry: _load,
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpace.lg),
      itemCount: _payrolls.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
      itemBuilder: (context, index) {
        final item = _payrolls[index];
        return AppCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.month,
                      style: AppType.h3.copyWith(color: AppColors.ink),
                    ),
                    Text(
                      'Net: ৳${item.netPay.toStringAsFixed(2)}',
                      style: AppType.meta.copyWith(color: AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
              // Pinned to success, matching the original — payroll status was
              // always green regardless of its value.
              AppStatusChip(
                status: item.status,
                color: AppColors.success,
                compact: true,
              ),
            ],
          ),
        );
      },
    );
  }
}
