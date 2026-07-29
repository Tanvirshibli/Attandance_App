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

class _SalesInfoScreenState extends State<SalesInfoScreen>
    with SingleTickerProviderStateMixin {
  final SalesService _salesService = SalesService();
  final AuthService _authService = AuthService();

  bool _isLoading = true;
  bool _isEligible = false;
  String? _unavailableReason;
  String? _employeeName;
  String? _error;
  String _period = 'This month';
  DateTime? _customFrom;
  DateTime? _customTo;
  SalesPersonSalesData? _data;
  int? _employeeId;
  int _moduleIndex = 0;

  TabController? _tabController;

  final _periods = const ['This month', 'Last month', 'Custom'];

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  void _ensureTabs(int count) {
    if (_tabController != null && _tabController!.length == count) return;
    _tabController?.dispose();
    _tabController = TabController(length: count, vsync: this);
    _tabController!.addListener(() {
      if (!_tabController!.indexIsChanging) {
        setState(() => _moduleIndex = _tabController!.index);
      }
    });
  }

  (DateTime, DateTime) _dateRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case 'Last month':
        final firstThis = DateTime(now.year, now.month, 1);
        final lastPrev = firstThis.subtract(const Duration(days: 1));
        final firstPrev = DateTime(lastPrev.year, lastPrev.month, 1);
        return (firstPrev, lastPrev);
      case 'Custom':
        final from = _customFrom ?? DateTime(now.year, now.month, 1);
        final to = _customTo ?? today;
        return (from, to);
      case 'This month':
      default:
        return (DateTime(now.year, now.month, 1), today);
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final from = await showDatePicker(
      context: context,
      initialDate: _customFrom ?? DateTime(now.year, now.month, 1),
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      helpText: 'From date',
    );
    if (from == null || !mounted) return;

    final to = await showDatePicker(
      context: context,
      initialDate: _customTo ?? now,
      firstDate: from,
      lastDate: now,
      helpText: 'To date',
    );
    if (to == null || !mounted) return;

    setState(() {
      _customFrom = from;
      _customTo = to;
      _period = 'Custom';
    });
    await _loadSales();
  }

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
        _unavailableReason = eligibility.data?.unavailableReason;
        _employeeName = eligibility.data?.employeeName ?? profile?.name;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isEligible = true;
      _unavailableReason = null;
      _employeeId = employeeId;
      _employeeName = eligibility.data?.employeeName ?? profile?.name;
    });

    await _loadSales();
  }

  Future<void> _loadSales() async {
    if (_employeeId == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final range = _dateRange();
    final result = await _salesService.getSalesPersonSales(
      employeeId: _employeeId!,
      fromDate: range.$1,
      toDate: range.$2,
    );

    if (!mounted) return;

    if (!result.success || result.data == null) {
      setState(() {
        _data = null;
        _error = result.message ?? 'Could not load sales.';
        _isLoading = false;
      });
      return;
    }

    final data = result.data!;
    _ensureTabs(data.modules.length);
    setState(() {
      _data = data;
      _employeeName = data.employee.employeeName?.isNotEmpty == true
          ? data.employee.employeeName
          : _employeeName;
      _error = null;
      _isLoading = false;
      if (_moduleIndex >= data.modules.length) {
        _moduleIndex = 0;
        _tabController?.index = 0;
      }
    });
  }

  Future<void> _onPeriodChanged(String period) async {
    if (period == 'Custom') {
      await _pickCustomRange();
      return;
    }
    setState(() => _period = period);
    await _loadSales();
  }

  Future<void> _openPostSale() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PostSaleScreen()),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _salesService.useCreateDemo
                ? 'Demo order saved (live sales disabled).'
                : 'Sale submitted successfully.',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
      await _loadSales();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: _isEligible
          ? FloatingActionButton.extended(
              onPressed: _openPostSale,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: Text(
                'Post sale / booking',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            )
          : null,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: GradientScreenHeader(
              title: 'Sales Info',
              subtitle: _employeeName ?? 'Your sales performance',
            ),
          ),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: ApiEmptyState(
                    icon: Icons.error_outline,
                    title: 'Could not load sales',
                    subtitle: _error!,
                    onRetry: _load,
                  ),
                ),
              ),
            )
          else if (!_isEligible)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: ApiEmptyState(
                    icon: Icons.trending_up_outlined,
                    title: _unavailableReason == SalesProfile.featureDisabled
                        ? 'Sales module disabled'
                        : 'Sales not available',
                    subtitle: _unavailableReason == SalesProfile.featureDisabled
                        ? 'Sales Info is turned off in mobile app settings. Ask an admin to enable the Sales module.'
                        : 'Your employee profile is not on the sales team list. Contact HR if this is unexpected.',
                  ),
                ),
              ),
            )
          else if (_data == null)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: ApiEmptyState(
                    icon: Icons.inbox_outlined,
                    title: 'No sales data',
                    subtitle: 'No sales found for the selected period.',
                    onRetry: _loadSales,
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  FadeInUp(
                    child: FilterChipRow(
                      options: _periods,
                      selected: _period,
                      onSelected: _onPeriodChanged,
                    ),
                  ),
                  if (_period == 'Custom' &&
                      _customFrom != null &&
                      _customTo != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${DateFormat('dd MMM yyyy').format(_customFrom!)}'
                      ' – ${DateFormat('dd MMM yyyy').format(_customTo!)}',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FadeInUp(
                    delay: const Duration(milliseconds: 60),
                    child: _OverallStrip(overall: _data!.overall),
                  ),
                  const SizedBox(height: 16),
                  FadeInUp(
                    delay: const Duration(milliseconds: 100),
                    child: _ModuleTabs(
                      controller: _tabController!,
                      modules: _data!.modules,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FadeInUp(
                    delay: const Duration(milliseconds: 140),
                    child: _ModulePanel(
                      module: _data!.modules[_moduleIndex],
                    ),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

class _OverallStrip extends StatelessWidget {
  const _OverallStrip({required this.overall});

  final SalesOverallSummary overall;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Overall',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _KpiChip(
                label: 'Orders',
                value: '${overall.totalOrders}',
              ),
              _KpiChip(
                label: 'Returns',
                value: '${overall.totalReturns}',
              ),
              _KpiChip(
                label: 'Net sales',
                value: moneyBdt(overall.netSales),
                emphasize: true,
              ),
              _KpiChip(
                label: 'Gross sales',
                value: moneyBdt(overall.grossSales),
              ),
              if (overall.quantityByUnit.isNotEmpty)
                for (final q in overall.quantityByUnit)
                  _KpiChip(
                    label: q.unitName?.trim().isNotEmpty == true
                        ? 'Net qty (${q.unitName})'
                        : 'Net qty',
                    value: qtyFmt(q.netQty),
                  )
              else
                _KpiChip(
                  label: 'Net qty',
                  value: qtyFmt(overall.netQty),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KpiChip extends StatelessWidget {
  const _KpiChip({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 96),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: emphasize
            ? AppColors.primary.withValues(alpha: 0.08)
            : AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: emphasize ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuleTabs extends StatelessWidget {
  const _ModuleTabs({
    required this.controller,
    required this.modules,
  });

  final TabController controller;
  final List<SalesModuleBlock> modules;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: Colors.white,
        unselectedLabelColor: AppColors.textSecondary,
        indicator: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(6),
        dividerColor: Colors.transparent,
        labelStyle: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.poppins(fontSize: 12),
        tabs: [
          for (final m in modules)
            Tab(
              height: 36,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(m.label),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModulePanel extends StatelessWidget {
  const _ModulePanel({required this.module});

  final SalesModuleBlock module;

  @override
  Widget build(BuildContext context) {
    if (module.isEmpty) {
      return SectionCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 36,
                color: AppColors.textSecondary.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 10),
              Text(
                'No ${module.label.toLowerCase()} sales',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Nothing recorded for this module in the selected period.',
                textAlign: TextAlign.center,
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

    final s = module.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${module.label} summary',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _KpiChip(label: 'Orders', value: '${s.totalOrders}'),
                  _KpiChip(label: 'Returns', value: '${s.totalReturns}'),
                  _KpiChip(
                    label: 'Net sales',
                    value: moneyBdt(s.netSales),
                    emphasize: true,
                  ),
                  _KpiChip(label: 'Net qty', value: qtyFmt(s.netQty)),
                  _KpiChip(
                    label: 'Gross sales',
                    value: moneyBdt(s.grossSales),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ExpandableListSection(
          title: 'Products',
          count: module.products.length,
          children: [
            for (final p in module.products)
              _NamedAmountRow(
                name: p.name,
                amount: p.netAmount,
                qty: p.netQty,
                unit: p.unitName,
              ),
          ],
        ),
        const SizedBox(height: 10),
        _ExpandableListSection(
          title: 'Dealers',
          count: module.dealers.length,
          children: [
            for (final d in module.dealers)
              _NamedAmountRow(
                name: d.name,
                amount: d.netAmount,
                qty: d.netQty,
              ),
          ],
        ),
        const SizedBox(height: 10),
        _ExpandableListSection(
          title: 'Sectors',
          count: module.sectors.length,
          children: [
            for (final s in module.sectors)
              _NamedAmountRow(
                name: s.name,
                amount: s.netAmount,
                qty: s.netQty,
              ),
          ],
        ),
        const SizedBox(height: 10),
        _ExpandableListSection(
          title: 'Line details',
          count: module.details.length,
          initiallyExpanded: module.details.length <= 8,
          children: [
            for (final line in module.details) _DetailTile(line: line),
          ],
        ),
      ],
    );
  }
}

class _ExpandableListSection extends StatelessWidget {
  const _ExpandableListSection({
    required this.title,
    required this.count,
    required this.children,
    this.initiallyExpanded = false,
  });

  final String title;
  final int count;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded && count > 0,
          title: Text(
            '$title ($count)',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: count == 0
              ? [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'No items',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ]
              : children,
        ),
      ),
    );
  }
}

class _NamedAmountRow extends StatelessWidget {
  const _NamedAmountRow({
    required this.name,
    required this.amount,
    required this.qty,
    this.unit,
  });

  final String name;
  final double amount;
  final double qty;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Qty ${qtyFmt(qty)}${unit != null && unit!.isNotEmpty ? ' $unit' : ''}',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            moneyBdt(amount),
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

class _DetailTile extends StatelessWidget {
  const _DetailTile({required this.line});

  final SalesDetailLine line;

  @override
  Widget build(BuildContext context) {
    final isReturn = line.type.toLowerCase().contains('return');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  line.referenceNo.isEmpty ? '#${line.orderId}' : line.referenceNo,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (isReturn ? AppColors.error : AppColors.success)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  line.type,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isReturn ? AppColors.error : AppColors.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${line.formattedDate} · ${line.status}',
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          if (line.dealerName != null && line.dealerName!.isNotEmpty)
            Text(
              line.dealerName!,
              style: GoogleFonts.poppins(fontSize: 12),
            ),
          if (line.productName != null && line.productName!.isNotEmpty)
            Text(
              line.productName!,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Qty ${qtyFmt(line.qty)}${line.unitName != null ? ' ${line.unitName}' : ''}',
                style: GoogleFonts.poppins(fontSize: 12),
              ),
              Text(
                moneyBdt(line.lineAmount),
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
