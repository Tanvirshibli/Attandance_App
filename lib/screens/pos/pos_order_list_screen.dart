import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_models.dart';
import '../../services/pos_service.dart';
import '../../widgets/date_range_field.dart';
import '../../widgets/ui/ui.dart';
import 'pos_order_detail_screen.dart';

class _CategoryChoice {
  const _CategoryChoice({
    required this.label,
    this.categoryId,
    this.subCategoryId,
    this.childCategoryId,
  });

  final String label;
  final int? categoryId;
  final int? subCategoryId;
  final int? childCategoryId;
}

/// Approved feed orders with POS Invoice / POS Challan receipts.
class PosOrderListScreen extends StatefulWidget {
  const PosOrderListScreen({super.key});

  @override
  State<PosOrderListScreen> createState() => _PosOrderListScreenState();
}

class _PosOrderListScreenState extends State<PosOrderListScreen> {
  final PosService _service = PosService();
  final ScrollController _scrollController = ScrollController();

  late DateTime _from = DateTime.now().subtract(const Duration(days: 29));
  late DateTime _to = DateTime.now();

  List<PosSector> _sectors = const [];
  PosSector? _sector;
  _CategoryChoice? _category;

  List<PosOrderSummary> _orders = const [];
  PosOrdersMeta _meta = const PosOrdersMeta();
  int _page = 1;

  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadSectors();
    _loadOrders(reset: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _loadSectors() async {
    final result = await _service.getSectors();
    if (!mounted || !result.success) return;
    setState(() => _sectors = result.data ?? const []);
  }

  Future<void> _loadOrders({required bool reset}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _error = null;
        _page = 1;
      });
    }

    final result = await _service.getOrders(
      sector: _sector?.name,
      categoryId: _category?.categoryId,
      subCategoryId: _category?.subCategoryId,
      childCategoryId: _category?.childCategoryId,
      startDate: _from,
      endDate: _to,
      page: reset ? 1 : _page,
      limit: 20,
    );

    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _error = result.message ?? 'Could not load approved orders.';
        if (reset) _orders = const [];
      });
      return;
    }

    final page = result.data ?? const PosOrdersPage();
    setState(() {
      _isLoading = false;
      _isLoadingMore = false;
      _error = null;
      _meta = page.meta;
      _page = reset ? 1 : _page;
      _orders = reset ? page.orders : [..._orders, ...page.orders];
    });
  }

  void _loadMore() {
    if (_isLoading || _isLoadingMore || _isLoadingMore) return;
    if (_page >= _meta.lastPage) return;

    setState(() {
      _isLoadingMore = true;
      _page += 1;
    });
    _loadOrders(reset: false);
  }

  void _onDateChanged(DateTime from, DateTime to) {
    setState(() {
      _from = from;
      _to = to;
    });
    _loadOrders(reset: true);
  }

  void _resetFilters() {
    setState(() {
      _sector = null;
      _category = null;
      _from = DateTime.now().subtract(const Duration(days: 29));
      _to = DateTime.now();
    });
    _loadOrders(reset: true);
  }

  Future<void> _pickCategory() async {
    if (_categoryTree.isEmpty) {
      final result = await _service.getCategories();
      if (!mounted || !result.success) return;
      setState(() => _categoryTree = result.data ?? const []);
    }
    if (!mounted) return;

    final choice = await showModalBottomSheet<_CategoryChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (context) => _CategoryPickerSheet(categories: _categoryTree),
    );

    if (!mounted || choice == null) return;
    setState(() => _category = choice);
    _loadOrders(reset: true);
  }

  List<PosCategory> _categoryTree = const [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: RefreshIndicator(
        onRefresh: () => _loadOrders(reset: true),
        color: AppColors.mSales,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            const SliverToBoxAdapter(
              child: AppHeader(
                title: 'POS Orders',
                subtitle: 'Approved feed orders',
              ),
            ),
            SliverToBoxAdapter(child: _filters()),
            SliverToBoxAdapter(child: _summaryChips()),
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: AppEmptyState(
                      icon: AppIcons.error,
                      title: 'Could not load orders',
                      subtitle: _error!,
                      onRetry: () => _loadOrders(reset: true),
                    ),
                  ),
                ),
              )
            else if (_orders.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: AppEmptyState(
                      icon: AppIcons.receipt,
                      title: 'No approved orders',
                      subtitle:
                          'Approved feed orders in this date range will appear here.',
                    ),
                  ),
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpace.gutter, AppSpace.xs, AppSpace.gutter, AppSpace.md),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _orderCard(_orders[index]),
                    childCount: _orders.length,
                  ),
                ),
              ),
              if (_page < _meta.lastPage)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(
                        bottom: AppSpace.xl, left: AppSpace.gutter, right: AppSpace.gutter),
                    child: _isLoadingMore
                        ? const Center(child: CircularProgressIndicator())
                        : AppButton(
                            label: 'Load more',
                            kind: AppButtonKind.secondary,
                            accent: AppColors.mSales,
                            onPressed: _loadMore,
                          ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<PosSector>(
                  initialValue: _sector,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Sales point',
                    prefixIcon: Icon(AppIcons.store, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<PosSector>(
                      value: null,
                      child: Text('All sales points'),
                    ),
                    for (final sector in _sectors)
                      DropdownMenuItem<PosSector>(
                        value: sector,
                        child: Text(sector.label,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() => _sector = value);
                    _loadOrders(reset: true);
                  },
                ),
                const SizedBox(height: AppSpace.sm),
                InkWell(
                  onTap: _pickCategory,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(AppIcons.filter, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _category?.label ?? 'All feed categories',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(AppIcons.chevron, size: 18),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          DateRangeField(
            from: _from,
            to: _to,
            onChanged: _onDateChanged,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: AppPillButton(
                icon: AppIcons.refresh,
                label: 'Reset',
                filled: false,
                color: AppColors.mSales,
                onTap: _resetFilters,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter, 0, AppSpace.gutter, AppSpace.sm),
      child: Wrap(
        spacing: AppSpace.xs,
        runSpacing: AppSpace.xs,
        children: [
          _chip('Approved Orders', _meta.approvedOrdersCount),
          _chip('Unique Selling Dealers', _meta.uniqueSellingDealers),
        ],
      ),
    );
  }

  Widget _chip(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm, vertical: AppSpace.xxs),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.line),
      ),
      child: Text(
        '$label: ${NumberFormat.decimalPattern().format(value)}',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _orderCard(PosOrderSummary order) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: AppCard(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PosOrderDetailScreen(orderId: order.id),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.feedId ?? '#${order.id}',
                    style: AppType.bodyStrong,
                  ),
                ),
                AppStatusChip(
                  status: order.status ?? 'unknown',
                  color: AppColors.success,
                ),
              ],
            ),
            const SizedBox(height: AppSpace.xxs),
            Text(
              [
                if (order.sector?.label.isNotEmpty ?? false) order.sector!.label,
                if (order.invoiceDate != null) 'Inv ${_date(order.invoiceDate)}',
                if (order.dueDate != null) 'Due ${_date(order.dueDate)}',
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              order.dealer?.displayName ?? '—',
              style: AppType.bodySm,
            ),
            if (order.salesPersonName != null &&
                order.salesPersonName!.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xxs),
              Text(
                'Sales person: ${order.salesPersonName}',
                style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
              ),
            ],
            const SizedBox(height: AppSpace.xs),
            for (final item in order.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '${item.sn}. ${item.productName ?? item.displayName}: '
                  '${item.quantityLabel} * ${formatPosNumber(item.salePrice)} /-',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            const SizedBox(height: AppSpace.xs),
            Row(
              children: [
                Expanded(child: _amount('Due A', order.dueAmount)),
                Expanded(child: _amount('Total A', order.totalAmount)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _amount(String label, double value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
        Text(value.toStringAsFixed(2), style: AppType.bodyStrong),
      ],
    );
  }

  static String _date(String? value) {
    final parsed = DateTime.tryParse(value ?? '');
    if (parsed == null) return '—';
    return DateFormat('dd MMM yyyy').format(parsed);
  }
}

class _CategoryPickerSheet extends StatelessWidget {
  const _CategoryPickerSheet({required this.categories});

  final List<PosCategory> categories;

  @override
  Widget build(BuildContext context) {
    final choices = <_CategoryChoice>[
      const _CategoryChoice(label: 'All feed categories'),
      for (final category in categories) ...[
        _CategoryChoice(
          label: category.name,
          categoryId: category.id,
        ),
        for (final sub in category.subCategories) ...[
          _CategoryChoice(
            label: '${category.name} › ${sub.name}',
            subCategoryId: sub.id,
          ),
          for (final child in sub.childCategories)
            _CategoryChoice(
              label: '${category.name} › ${sub.name} › ${child.name}',
              childCategoryId: child.id,
            ),
        ],
      ],
    ];

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.gutter, AppSpace.md, AppSpace.gutter, AppSpace.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Select category', style: AppType.h3),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(PhosphorIconsDuotone.x),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: choices.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final choice = choices[index];
                  return ListTile(
                    title: Text(choice.label),
                    onTap: () => Navigator.pop(context, choice),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
