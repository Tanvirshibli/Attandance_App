import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../config/theme.dart';
import '../models/auth_wise_payment_models.dart';
import '../models/sales_models.dart' show moneyBdt;
import '../services/auth_service.dart';
import '../services/payment_service.dart';
import '../widgets/api_empty_state.dart';
import '../widgets/filter_chip_row.dart';
import '../widgets/gradient_screen_header.dart';
import '../widgets/section_card.dart';
import 'compensation_screen.dart';
import 'loan_list_screen.dart';
import 'mess_deposit_screen.dart';
import 'payment_report_screen.dart';
import 'payslip_list_screen.dart';
import 'post_payment_screen.dart';
import 'provident_fund_screen.dart';

class PaymentHubScreen extends StatefulWidget {
  const PaymentHubScreen({super.key});

  @override
  State<PaymentHubScreen> createState() => _PaymentHubScreenState();
}

class _PaymentHubScreenState extends State<PaymentHubScreen>
    with SingleTickerProviderStateMixin {
  final PaymentService _paymentService = PaymentService();
  final AuthService _authService = AuthService();

  bool _isLoading = true;
  bool _featureDisabled = false;
  String? _employeeName;
  String? _error;
  String _period = 'This month';
  DateTime? _customFrom;
  DateTime? _customTo;
  AuthWisePaymentsData? _data;
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
    await _loadPayments();
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
      _featureDisabled = false;
    });

    final profile = await _authService.getCurrentUserProfile();
    final employeeId = profile?.canonicalEmployeeId ?? 0;

    if (!await _paymentService.isPaymentEnabled()) {
      if (!mounted) return;
      setState(() {
        _featureDisabled = true;
        _employeeName = profile?.name;
        _isLoading = false;
      });
      return;
    }

    if (employeeId <= 0) {
      if (!mounted) return;
      setState(() {
        _error = 'Missing employee profile.';
        _employeeName = profile?.name;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _employeeId = employeeId;
      _employeeName = profile?.name;
    });

    await _loadPayments();
  }

  Future<void> _loadPayments() async {
    if (_employeeId == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final range = _dateRange();
    final result = await _paymentService.getAuthWisePayments(
      employeeId: _employeeId!,
      fromDate: range.$1,
      toDate: range.$2,
    );

    if (!mounted) return;

    if (!result.success || result.data == null) {
      final msg = result.message ?? 'Could not load payments.';
      setState(() {
        _data = null;
        _featureDisabled = msg == 'feature_disabled';
        _error = msg == 'feature_disabled' ? null : msg;
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
      _featureDisabled = false;
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
    await _loadPayments();
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
            SliverToBoxAdapter(
              child: GradientScreenHeader(
                title: 'Payments',
                subtitle: _employeeName ?? 'Dealer payments & HR benefits',
              ),
            ),
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_featureDisabled)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ApiEmptyState(
                      icon: Icons.payments_outlined,
                      title: 'Payments module disabled',
                      subtitle:
                          'Dealer payments are turned off in mobile app settings. Ask an admin to enable the Payment module.',
                      onRetry: _load,
                    ),
                  ),
                ),
              )
            else if (_error != null)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ApiEmptyState(
                      icon: Icons.error_outline,
                      title: 'Could not load payments',
                      subtitle: _error!,
                      onRetry: _load,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (_data != null) ...[
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
                      if (_tabController != null) ...[
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
                      ],
                      const SizedBox(height: 28),
                    ],
                    Text(
                      'HR benefits',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Payslips, loans, PF and related HR records',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (_paymentService.useDemoData) ...[
                      const SizedBox(height: 10),
                      _demoBanner(),
                    ],
                    const SizedBox(height: 12),
                    _hubCard(
                      delay: 0,
                      icon: Icons.receipt_long_rounded,
                      title: 'Payslips',
                      subtitle: 'Monthly salary breakdown',
                      color: AppColors.primary,
                      screen: const PayslipListScreen(),
                    ),
                    _hubCard(
                      delay: 40,
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'My loans',
                      subtitle: 'Active loans & balances',
                      color: AppColors.warning,
                      screen: const LoanListScreen(),
                    ),
                    _hubCard(
                      delay: 80,
                      icon: Icons.history_rounded,
                      title: 'Loan payments',
                      subtitle: 'Repayment history & payroll slips',
                      color: AppColors.info,
                      screen: const PaymentReportScreen(),
                    ),
                    _hubCard(
                      delay: 120,
                      icon: Icons.add_card_outlined,
                      title: 'Post payment',
                      subtitle: 'Submit a loan repayment',
                      color: AppColors.success,
                      screen: const PostPaymentScreen(),
                    ),
                    _hubCard(
                      delay: 160,
                      icon: Icons.savings_outlined,
                      title: 'Provident fund',
                      subtitle: 'PF balance & history',
                      color: const Color(0xFF7C4DFF),
                      screen: const ProvidentFundScreen(),
                    ),
                    _hubCard(
                      delay: 200,
                      icon: Icons.restaurant_outlined,
                      title: 'Mess deposit',
                      subtitle: 'Latest mess contribution',
                      color: AppColors.error,
                      screen: const MessDepositScreen(),
                    ),
                    _hubCard(
                      delay: 240,
                      icon: Icons.badge_outlined,
                      title: 'Compensation',
                      subtitle: 'Salary structure allowances',
                      color: AppColors.accent,
                      screen: const CompensationScreen(),
                    ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _demoBanner() {
    return Container(
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
              'HR benefits below use demo payroll/loan data',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hubCard({
    required int delay,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Widget screen,
  }) {
    return FadeInUp(
      delay: Duration(milliseconds: delay),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SectionCard(
          padding: EdgeInsets.zero,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => screen),
            ),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OverallStrip extends StatelessWidget {
  const _OverallStrip({required this.overall});

  final AuthWiseOverallSummary overall;

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
              _KpiChip(label: 'Payments', value: '${overall.totalPayments}'),
              _KpiChip(
                label: 'Total amount',
                value: moneyBdt(overall.totalAmount),
                emphasize: true,
              ),
              _KpiChip(label: 'Dealers', value: '${overall.totalDealers}'),
              _KpiChip(label: 'Companies', value: '${overall.totalCompanies}'),
              _KpiChip(
                label: 'Payment modes',
                value: '${overall.totalPaymentModes}',
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
  final List<AuthWisePaymentModule> modules;

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

  final AuthWisePaymentModule module;

  @override
  Widget build(BuildContext context) {
    if (module.isEmpty) {
      return SectionCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              Icon(
                Icons.payments_outlined,
                size: 36,
                color: AppColors.textSecondary.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 10),
              Text(
                'No ${module.label.toLowerCase()} payments',
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
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _KpiChip(label: 'Payments', value: '${s.totalPayments}'),
              _KpiChip(
                label: 'Amount',
                value: moneyBdt(s.totalAmount),
                emphasize: true,
              ),
              _KpiChip(label: 'Dealers', value: '${s.totalDealers}'),
              _KpiChip(label: 'Companies', value: '${s.totalCompanies}'),
            ],
          ),
          if (module.dealers.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ExpandableNamedList(title: 'Dealers', rows: module.dealers),
          ],
          if (module.companies.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ExpandableNamedList(title: 'Companies', rows: module.companies),
          ],
          if (module.paymentMethods.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ExpandableMethods(methods: module.paymentMethods),
          ],
          if (module.details.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ExpandableLines(lines: module.details),
          ],
        ],
      ),
    );
  }
}

class _ExpandableNamedList extends StatelessWidget {
  const _ExpandableNamedList({required this.title, required this.rows});

  final String title;
  final List<AuthWiseNamedTotal> rows;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          '$title (${rows.length})',
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        children: [
          for (final row in rows)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                row.name,
                style: GoogleFonts.poppins(fontSize: 13),
              ),
              subtitle: Text(
                '${row.totalPayments} payment(s)',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              trailing: Text(
                moneyBdt(row.totalAmount),
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

class _ExpandableMethods extends StatelessWidget {
  const _ExpandableMethods({required this.methods});

  final List<AuthWisePaymentMethodTotal> methods;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          'Payment methods (${methods.length})',
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        children: [
          for (final m in methods)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                m.label,
                style: GoogleFonts.poppins(fontSize: 13),
              ),
              subtitle: Text(
                [
                  if (m.bankAccountNo != null && m.bankAccountNo!.isNotEmpty)
                    m.bankAccountNo,
                  '${m.totalPayments} payment(s)',
                ].whereType<String>().join(' · '),
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              trailing: Text(
                moneyBdt(m.totalAmount),
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

class _ExpandableLines extends StatelessWidget {
  const _ExpandableLines({required this.lines});

  final List<AuthWisePaymentLine> lines;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          'Payment details (${lines.length})',
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                width: double.infinity,
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
                            line.voucherNo?.isNotEmpty == true
                                ? line.voucherNo!
                                : 'Payment #${line.id}',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          line.formattedAmount,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        line.formattedDate,
                        if (line.dealerName != null &&
                            line.dealerName!.isNotEmpty)
                          line.dealerName,
                        if (line.companyName != null &&
                            line.companyName!.isNotEmpty)
                          line.companyName,
                      ].join(' · '),
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (line.bankName != null || line.checkNo != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (line.bankShortName?.isNotEmpty == true)
                            line.bankShortName
                          else if (line.bankName?.isNotEmpty == true)
                            line.bankName,
                          if (line.checkNo?.isNotEmpty == true)
                            'Cheque ${line.checkNo}',
                        ].whereType<String>().join(' · '),
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
        ],
      ),
    );
  }
}
