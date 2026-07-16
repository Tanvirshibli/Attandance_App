import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../config/theme.dart';
import '../models/sales_models.dart';
import '../services/auth_service.dart';
import '../services/sales_service.dart';
import '../widgets/api_empty_state.dart';
import '../widgets/filter_chip_row.dart';
import '../widgets/gradient_screen_header.dart';
import '../widgets/section_card.dart';
import 'post_sale_screen.dart';

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
  String? _employeeName;
  String? _error;
  String _period = 'This month';
  SalesOverview? _overview;
  List<SalePosting> _postings = const [];
  int? _employeeId;

  final _periods = const ['This month', 'Last month', 'Custom'];
  final _money = NumberFormat.currency(symbol: '৳', decimalDigits: 0);

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

    final profile = await _authService.getCurrentUserProfile();
    final employeeId = profile?.canonicalEmployeeId ?? 0;
    final eligibility = await _salesService.checkEligibility(
      profile?.canonicalEmployeeId,
    );

    if (!mounted) return;

    if (!eligibility.success) {
      setState(() {
        _isLoading = false;
        _error = eligibility.message;
      });
      return;
    }

    final eligible = eligibility.data?.isEligible ?? false;
    if (!eligible) {
      setState(() {
        _isEligible = false;
        _employeeName = eligibility.data?.employeeName ?? profile?.name;
        _isLoading = false;
      });
      return;
    }

    final overview = await _salesService.getOverview(
      employeeId: employeeId,
      period: _period,
    );
    final postings = await _salesService.getMyPostings(employeeId: employeeId);

    if (!mounted) return;
    setState(() {
      _isEligible = true;
      _employeeId = employeeId;
      _employeeName = eligibility.data?.employeeName ?? profile?.name;
      _overview = overview.data;
      _postings = postings.data ?? const [];
      _error = overview.success
          ? (postings.success ? null : postings.message)
          : overview.message;
      _isLoading = false;
    });
  }

  Future<void> _onPeriodChanged(String period) async {
    setState(() => _period = period);
    if (_employeeId == null) return;
    setState(() => _isLoading = true);
    final overview = await _salesService.getOverview(
      employeeId: _employeeId!,
      period: period,
    );
    if (!mounted) return;
    setState(() {
      _overview = overview.data;
      _isLoading = false;
    });
  }

  Future<void> _openPostSale() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PostSaleScreen()),
    );
    if (created == true) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: _isEligible && !_isLoading
          ? FadeInUp(
              child: FloatingActionButton.extended(
                onPressed: _openPostSale,
                backgroundColor: AppColors.primary,
                icon: const Icon(Icons.add_rounded, color: Colors.white),
                label: Text(
                  'Post sale',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: GradientScreenHeader(
                title: 'Sales Info',
                subtitle: _employeeName ?? 'Your personal sales dashboard',
              ),
            ),
            if (_salesService.useDemoData && _isEligible)
              SliverToBoxAdapter(child: _demoBanner()),
            if (_isLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_error != null && !_isEligible)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: ApiEmptyState(
                    icon: Icons.wifi_off_rounded,
                    title: 'Could not load',
                    subtitle: _error,
                    onRetry: _load,
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
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: FilterChipRow(
                    options: _periods,
                    selected: _period,
                    onSelected: _onPeriodChanged,
                  ),
                ),
              ),
              if (_overview != null) ...[
                SliverToBoxAdapter(child: _progressCard(_overview!)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.25,
                    ),
                    delegate: SliverChildListDelegate([
                      _kpiCard(
                        'Target',
                        _money.format(_overview!.targetAmount),
                        Icons.flag_outlined,
                        AppColors.primary,
                        0,
                      ),
                      _kpiCard(
                        'Achieved',
                        _money.format(_overview!.achievedAmount),
                        Icons.trending_up_rounded,
                        AppColors.success,
                        80,
                      ),
                      _kpiCard(
                        'Orders',
                        '${_overview!.ordersCount}',
                        Icons.shopping_bag_outlined,
                        AppColors.warning,
                        160,
                      ),
                      _kpiCard(
                        'Conversion',
                        '${_overview!.conversionRate.toStringAsFixed(1)}%',
                        Icons.percent_rounded,
                        AppColors.info,
                        240,
                      ),
                    ]),
                  ),
                ),
              ],
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Row(
                    children: [
                      Text(
                        'My sales',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_postings.length} posts',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_postings.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ApiEmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No sales yet',
                      subtitle: 'Post your first sale to see it here.',
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = _postings[index];
                        return FadeInUp(
                          delay: Duration(milliseconds: 40 * index),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _saleTile(item),
                          ),
                        );
                      },
                      childCount: _postings.length,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _demoBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(Icons.science_outlined, size: 18, color: AppColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Demo data — switch to live when the sales API is ready',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressCard(SalesOverview overview) {
    final pct = (overview.progressRatio * 100).clamp(0, 999);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: FadeInUp(
        child: SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Target progress',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${pct.toStringAsFixed(0)}%',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: overview.progressRatio.clamp(0.0, 1.0),
                  minHeight: 10,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${_money.format(overview.achievedAmount)} of ${_money.format(overview.targetAmount)}',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              if (overview.visitsCount != null) ...[
                const SizedBox(height: 6),
                Text(
                  '${overview.visitsCount} field visits · ${_money.format(overview.revenue)} revenue',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _kpiCard(
    String title,
    String value,
    IconData icon,
    Color color,
    int delayMs,
  ) {
    return FadeInUp(
      delay: Duration(milliseconds: delayMs),
      child: SectionCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const Spacer(),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _saleTile(SalePosting item) {
    final statusColor = switch (item.status.toLowerCase()) {
      'approved' => AppColors.success,
      'rejected' => AppColors.error,
      _ => AppColors.warning,
    };

    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.storefront_rounded, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.customerName,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    item.formattedDate,
                    if (item.productName != null) item.productName!,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                item.formattedAmount,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  item.status,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
