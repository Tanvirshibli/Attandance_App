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
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: ApiEmptyState(
                    icon: Icons.restaurant_outlined,
                    title: 'No mess deposit',
                    subtitle: 'Approved mess deposits will appear here.',
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _record!.formattedAmount,
                            style: GoogleFonts.poppins(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'This transaction',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 20),
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
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
