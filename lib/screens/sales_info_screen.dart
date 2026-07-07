import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import '../services/auth_service.dart';
import '../services/sales_service.dart';
import '../widgets/api_empty_state.dart';
import '../widgets/gradient_screen_header.dart';
import '../widgets/section_card.dart';

class SalesInfoScreen extends StatefulWidget {
  const SalesInfoScreen({super.key});

  @override
  State<SalesInfoScreen> createState() => _SalesInfoScreenState();
}

class _SalesInfoScreenState extends State<SalesInfoScreen> {
  final SalesService _salesService = SalesService();
  final AuthService _authService = AuthService();

  bool _isLoading = true;
  bool _isEligible = false;
  bool _salesEnabled = false;
  String? _employeeName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final salesEnabled = await _salesService.isSalesEnabled();
    final profile = await _authService.getCurrentUserProfile();
    final result = await _salesService.checkEligibility(
      profile?.canonicalEmployeeId,
    );
    if (!mounted) return;
    setState(() {
      _salesEnabled = salesEnabled;
      _isEligible = result.data?.isEligible ?? false;
      _employeeName = result.data?.employeeName ?? profile?.name;
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
              title: 'Sales Info',
              subtitle: _employeeName,
            ),
          ),
          if (_isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (!_salesEnabled)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: ApiEmptyState(
                  icon: Icons.hourglass_top_rounded,
                  title: 'Coming Soon',
                  subtitle:
                      'Sales reporting will be available once the sales backend is connected via the ZKTeco API dashboard.',
                ),
              ),
            )
          else if (!_isEligible)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: ApiEmptyState(
                  icon: Icons.storefront_outlined,
                  title: 'Not applicable for your role',
                  subtitle:
                      'Sales dashboard is available for sales & marketing team members.',
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.1,
                ),
                delegate: SliverChildListDelegate([
                  _metricCard('Monthly Target', '—', Icons.flag_outlined),
                  _metricCard('Orders', '—', Icons.shopping_bag_outlined),
                  _metricCard('Revenue', '—', Icons.attach_money_rounded),
                  _metricCard('Conversion', '—', Icons.percent_rounded),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _metricCard(String title, String value, IconData icon) {
    return FadeInUp(
      child: SectionCard(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: AppColors.warning),
                const Spacer(),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Soon',
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: AppColors.warning,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
