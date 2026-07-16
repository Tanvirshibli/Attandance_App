import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../config/theme.dart';
import '../models/payment_models.dart';
import '../services/auth_service.dart';
import '../services/payment_service.dart';
import '../widgets/gradient_screen_header.dart';
import '../widgets/section_card.dart';

class PostPaymentScreen extends StatefulWidget {
  const PostPaymentScreen({super.key});

  @override
  State<PostPaymentScreen> createState() => _PostPaymentScreenState();
}

class _PostPaymentScreenState extends State<PostPaymentScreen> {
  final PaymentService _paymentService = PaymentService();
  final AuthService _authService = AuthService();
  final _amountController = TextEditingController();

  List<EmployeeLoan> _loans = const [];
  EmployeeLoan? _selectedLoan;
  DateTime _paymentDate = DateTime.now();
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadLoans();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadLoans() async {
    final profile = await _authService.getCurrentUserProfile();
    final employeeId = profile?.canonicalEmployeeId ?? 0;

    final result = await _paymentService.getEmployeeLoans(employeeId);
    if (!mounted) return;
    setState(() {
      _loans = result.data ?? const [];
      _selectedLoan = _loans.isNotEmpty ? _loans.first : null;
      _isLoading = false;
    });
  }

  Future<void> _submit() async {
    final profile = await _authService.getCurrentUserProfile();
    final employeeId = profile?.canonicalEmployeeId ?? 0;
    if (_selectedLoan == null) {
      _showSnack('Select a loan to continue.');
      return;
    }

    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      _showSnack('Enter a valid amount.');
      return;
    }

    setState(() => _isSubmitting = true);
    final result = await _paymentService.postLoanPayment(
      employeeId: employeeId,
      loanId: _selectedLoan!.id,
      amount: amount,
      date: DateFormat('yyyy-MM-dd').format(_paymentDate),
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result.success) {
      _showSnack(result.data ?? 'Payment submitted.');
      Navigator.of(context).pop();
    } else {
      _showSnack(result.message ?? 'Submission failed.');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const GradientScreenHeader(title: 'Post Payment'),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Loan',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<EmployeeLoan>(
                            value: _selectedLoan,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: AppColors.background,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            items: _loans
                                .map(
                                  (l) => DropdownMenuItem(
                                    value: l,
                                    child: Text(
                                      '${l.label} — ${l.amount.toStringAsFixed(0)} (${l.status})',
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => _selectedLoan = v),
                          ),
                          if (_loans.isEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'No active loans found.',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: AppColors.warning,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          TextField(
                            controller: _amountController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Amount',
                              filled: true,
                              fillColor: AppColors.background,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'Payment Date',
                              style: GoogleFonts.poppins(fontSize: 12),
                            ),
                            subtitle: Text(
                              DateFormat('dd MMM yyyy').format(_paymentDate),
                            ),
                            trailing: const Icon(Icons.calendar_today_outlined),
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _paymentDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                              );
                              if (picked != null) {
                                setState(() => _paymentDate = picked);
                              }
                            },
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed:
                                  _isSubmitting || _loans.isEmpty ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: _isSubmitting
                                  ? const CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    )
                                  : Text(
                                      'Submit Payment',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
