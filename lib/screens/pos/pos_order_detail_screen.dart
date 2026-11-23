import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_models.dart';
import '../../services/pos_service.dart';
import '../../widgets/ui/ui.dart';
import 'pos_receipt_preview_screen.dart';

/// One approved feed order with its POS receipt actions.
class PosOrderDetailScreen extends StatefulWidget {
  const PosOrderDetailScreen({super.key, required this.orderId});

  final int orderId;

  @override
  State<PosOrderDetailScreen> createState() => _PosOrderDetailScreenState();
}

class _PosOrderDetailScreenState extends State<PosOrderDetailScreen> {
  final PosService _service = PosService();

  PosOrderDetail? _order;
  bool _isLoading = true;
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

    final result = await _service.getOrder(widget.orderId);
    if (!mounted) return;

    setState(() {
      _order = result.success ? result.data : null;
      _error = result.success
          ? null
          : (result.message ?? 'Could not load the order.');
      _isLoading = false;
    });
  }

  void _openPreview(PosDocType docType) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PosReceiptPreviewScreen(
          orderId: widget.orderId,
          docType: docType,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: AppEmptyState(
                      icon: AppIcons.error,
                      title: 'Could not load the order',
                      subtitle: _error!,
                      onRetry: _load,
                    ),
                  ),
                )
              : order == null
                  ? const SizedBox.shrink()
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppColors.mSales,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        slivers: [
                          SliverToBoxAdapter(
                            child: AppHeader(
                              title: order.feedId ?? 'Feed order',
                              subtitle: order.sector?.label,
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpace.gutter,
                              AppSpace.md,
                              AppSpace.gutter,
                              AppSpace.md,
                            ),
                            sliver: SliverList(
                              delegate: SliverChildListDelegate([
                                _summaryCard(order),
                                const SizedBox(height: AppSpace.sm),
                                _itemsCard(order),
                                const SizedBox(height: AppSpace.sm),
                                _totalsCard(order),
                                const SizedBox(height: AppSpace.fabClearance),
                              ]),
                            ),
                          ),
                        ],
                      ),
                    ),
      bottomNavigationBar: order == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(
                AppSpace.gutter,
                AppSpace.xs,
                AppSpace.gutter,
                AppSpace.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'POS Invoice',
                      icon: AppIcons.invoice,
                      accent: AppColors.mSales,
                      onPressed: () => _openPreview(PosDocType.invoice),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: AppButton(
                      label: 'POS Challan',
                      icon: AppIcons.receipt,
                      kind: AppButtonKind.secondary,
                      accent: AppColors.mSales,
                      onPressed: () => _openPreview(PosDocType.challan),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _summaryCard(PosOrderDetail order) {
    return AppCard(
      accent: AppColors.mSales,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.dealer?.displayName ?? '—',
                  style: AppType.bodyStrong,
                ),
              ),
              AppStatusChip(
                status: order.status ?? 'unknown',
                color: AppColors.success,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          _field('Dealer phone', order.dealer?.phone),
          _field('Sales person', order.salesPersonName),
          _field('Invoice date', _date(order.invoiceDateValue)),
          _field('Due date', _date(order.dueDateValue)),
          _field('Delivery address', order.deliveryAddress),
          _field('Driver', [
            if (order.driver.name != null) order.driver.name!,
            if (order.driver.phone != null) order.driver.phone!,
            if (order.driver.address != null) order.driver.address!,
          ].join(' · ')),
        ],
      ),
    );
  }

  Widget _itemsCard(PosOrderDetail order) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Items', style: AppType.h3),
          const SizedBox(height: AppSpace.xs),
          for (final item in order.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    child: Text('${item.sn}.',
                        style: const TextStyle(fontSize: 12)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.displayName, style: AppType.bodySm),
                        Text(
                          item.quantityLabel,
                          style: TextStyle(
                              fontSize: 12, color: AppColors.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(formatPosNumber(item.salePrice),
                          style: AppType.bodySm),
                      Text(
                        item.amount.toStringAsFixed(2),
                        style: AppType.bodyStrong,
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _totalsCard(PosOrderDetail order) {
    final totals = order.totals;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Totals', style: AppType.h3),
          const SizedBox(height: AppSpace.xs),
          _totalRow('Subtotal', totals.subTotal),
          _totalRow('Discount', totals.discountTotal),
          _totalRow('VAT (${formatPosNumber(totals.vatPercent)}%)',
              totals.totalTax),
          _totalRow('Transport', totals.transportCost),
          _totalRow('Others cost', totals.othersCost),
          _totalRow('Advance', totals.advanceAmount),
          const Divider(height: AppSpace.md),
          _totalRow('Due', totals.dueAmount, strong: true),
          _totalRow('Total', totals.totalAmount, strong: true),
          if (totals.amountInWords.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(
              'In words: ${totals.amountInWords}',
              style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(String label, String? value) {
    if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _totalRow(String label, double value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppType.bodySm),
          Text(
            value.toStringAsFixed(2),
            style: strong ? AppType.bodyStrong : AppType.bodySm,
          ),
        ],
      ),
    );
  }

  static String _date(DateTime? date) {
    if (date == null) return '—';
    return DateFormat('dd MMM yyyy').format(date);
  }
}
