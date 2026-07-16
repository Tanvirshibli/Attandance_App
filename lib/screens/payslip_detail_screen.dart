import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../config/theme.dart';
import '../models/payment_models.dart';
import '../services/payment_service.dart';
import '../widgets/api_empty_state.dart';
import '../widgets/gradient_screen_header.dart';
import '../widgets/section_card.dart';

class PayslipDetailScreen extends StatefulWidget {
  const PayslipDetailScreen({super.key, required this.payrollId});

  final int payrollId;

  @override
  State<PayslipDetailScreen> createState() => _PayslipDetailScreenState();
}

class _PayslipDetailScreenState extends State<PayslipDetailScreen> {
  final PaymentService _paymentService = PaymentService();
  final _money = NumberFormat.currency(symbol: '৳', decimalDigits: 0);

  bool _isLoading = true;
  PayrollRecord? _record;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final result = await _paymentService.getPayslipDetail(widget.payrollId);
    if (!mounted) return;
    setState(() {
      _record = result.data;
      _error = result.success ? null : result.message;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: GradientScreenHeader(
              title: _record?.month ?? 'Payslip',
              subtitle: _record?.designation ?? 'Salary breakdown',
            ),
          ),
          if (_isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_error != null || _record == null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: ApiEmptyState(
                  icon: Icons.error_outline,
                  title: 'Could not load payslip',
                  subtitle: _error,
                  onRetry: _load,
                ),
              ),
            )
          else ...[
            SliverToBoxAdapter(child: _netBanner(_record!)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              sliver: SliverToBoxAdapter(
                child: FadeInUp(
                  child: _section(
                    'Earnings',
                    [
                      _row('Basic', _record!.basics),
                      _row('House', _record!.houses),
                      _row('Medical', _record!.medicals),
                      _row('Food', _record!.foods),
                      _row('Gross (sGross)', _record!.sGross),
                      _row('Others payable', _record!.othersPayable),
                    ],
                    AppColors.success,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              sliver: SliverToBoxAdapter(
                child: FadeInUp(
                  delay: const Duration(milliseconds: 80),
                  child: _section(
                    'Deductions',
                    [
                      _row('Mess', _record!.mess),
                      _row('Absence', _record!.absenceDeduction),
                      _row('Provident fund', _record!.providentFund),
                      _row('Loan', _record!.loan),
                      _row('Mess deposit', _record!.messDeposit),
                      _row('Tax', _record!.tax),
                      _row('Service bill', _record!.serviceBill),
                      _row('Punishment', _record!.punishment),
                      _row('Others', _record!.others),
                      _row('Adjustment', _record!.adjustment),
                    ],
                    AppColors.error,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              sliver: SliverToBoxAdapter(
                child: FadeInUp(
                  delay: const Duration(milliseconds: 140),
                  child: _section(
                    'Attendance',
                    [
                      _intRow('Present days', _record!.presentDays),
                      _intRow('Absent days', _record!.absentDays),
                      _intRow('Holidays', _record!.holidays),
                      _intRow('Leaves', _record!.leaves),
                    ],
                    AppColors.info,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _netBanner(PayrollRecord record) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: FadeInUp(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: AppColors.successGradient,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Net receivable',
                style: GoogleFonts.poppins(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                record.formattedNet,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                [
                  'Net pay ${_money.format(record.netPay)}',
                  if (record.paymentMethod != null) record.paymentMethod!,
                  record.status,
                ].join(' · '),
                style: GoogleFonts.poppins(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> rows, Color accent) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...rows,
        ],
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

  Widget _intRow(String label, int? value) {
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
            '$value',
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
