import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import '../models/payment_models.dart';
import '../services/payment_service.dart';
import '../widgets/api_empty_state.dart';
import '../widgets/gradient_screen_header.dart';
import '../widgets/section_card.dart';

class LoanDetailScreen extends StatefulWidget {
  const LoanDetailScreen({super.key, required this.loanId});

  final int loanId;

  @override
  State<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends State<LoanDetailScreen> {
  final PaymentService _paymentService = PaymentService();

  bool _isLoading = true;
  EmployeeLoan? _loan;
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
    final result = await _paymentService.getLoanDetail(widget.loanId);
    if (!mounted) return;
    setState(() {
      _loan = result.data;
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
              title: _loan?.label ?? 'Loan detail',
              subtitle: _loan?.loanType ?? 'Loan information',
            ),
          ),
          if (_isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_loan == null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: ApiEmptyState(
                  icon: Icons.error_outline,
                  title: 'Loan not found',
                  subtitle: _error,
                  onRetry: _load,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              sliver: SliverToBoxAdapter(
                child: FadeInUp(
                  child: SectionCard(
                    child: Column(
                      children: [
                        _row('Status', _loan!.status),
                        _row('Amount', _loan!.formattedAmount),
                        _row('Remaining', _loan!.formattedRemaining),
                        if (_loan!.installmentAmount != null)
                          _row(
                            'Installment',
                            '৳${_loan!.installmentAmount!.toStringAsFixed(0)}',
                          ),
                        if (_loan!.installmentCount != null)
                          _row('Installments', '${_loan!.installmentCount}'),
                        if (_loan!.installmentType != null)
                          _row('Type', _loan!.installmentType!),
                        if (_loan!.interestPercentage != null)
                          _row(
                            'Interest %',
                            _loan!.interestPercentage!.toStringAsFixed(1),
                          ),
                        if (_loan!.loanAddDate != null)
                          _row('Added', _loan!.loanAddDate!),
                        if (_loan!.deadlineDate != null)
                          _row('Deadline', _loan!.deadlineDate!),
                        if (_loan!.note != null && _loan!.note!.isNotEmpty)
                          _row('Note', _loan!.note!),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
