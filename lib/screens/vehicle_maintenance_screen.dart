import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';

import '../models/sales_models.dart' show moneyBdt;
import '../models/vehicle_models.dart';
import '../services/vehicle_service.dart';
import '../widgets/ui/ui.dart';

class VehicleMaintenanceScreen extends StatefulWidget {
  const VehicleMaintenanceScreen({super.key, required this.vehicle});

  final VehicleSummary vehicle;

  @override
  State<VehicleMaintenanceScreen> createState() =>
      _VehicleMaintenanceScreenState();
}

class _VehicleMaintenanceScreenState extends State<VehicleMaintenanceScreen> {
  final VehicleService _vehicleService = VehicleService();

  bool _isLoading = true;
  String? _error;
  VehicleMaintenanceHistory? _history;

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

    final result =
        await _vehicleService.getMaintenanceHistory(widget.vehicle.id);
    if (!mounted) return;

    if (!result.success || result.data == null) {
      setState(() {
        _history = null;
        _error = result.message == 'feature_disabled'
            ? 'Vehicles module is disabled.'
            : (result.message ?? 'Could not load maintenance.');
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _history = result.data;
      _error = null;
      _isLoading = false;
    });
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return AppColors.success;
      case 'pending':
      case 'in_progress':
      case 'in-progress':
        return AppColors.warning;
      case 'cancelled':
      case 'canceled':
        return AppColors.error;
      default:
        return AppColors.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = widget.vehicle;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: AppHeader(
                title: vehicle.displayPlate,
                subtitle: 'Maintenance history',
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.md, AppSpace.gutter, 0),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vehicle.displayPlate,
                        style: AppType.h2.copyWith(color: AppColors.ink),
                      ),
                      const SizedBox(height: AppSpace.xxs),
                      Text(
                        'Vehicle no: ${vehicle.tVehicleNo.isEmpty ? '—' : vehicle.tVehicleNo}',
                        style: AppType.meta
                            .copyWith(color: AppColors.inkMuted),
                      ),
                      Text(
                        'Purchased: ${vehicle.formattedPurchaseDate}',
                        style: AppType.meta
                            .copyWith(color: AppColors.inkMuted),
                      ),
                      if (_history != null)
                        Text(
                          'Jobs shown: ${_history!.total}',
                          style:
                              AppType.meta.copyWith(color: AppColors.inkFaint),
                        ),
                    ],
                  ),
                ),
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
                    child: AppEmptyState(
                      icon: AppIcons.error,
                      title: 'Could not load history',
                      subtitle: _error!,
                      onRetry: _load,
                    ),
                  ),
                ),
              )
            else if (_history == null || _history!.jobs.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpace.lg),
                    child: AppEmptyState(
                      icon: AppIcons.wrench,
                      title: 'No maintenance jobs',
                      subtitle:
                          'Recent maintenance jobs for this vehicle will appear here.',
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.md, AppSpace.gutter, AppSpace.xl),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final job = _history!.jobs[index];
                      return FadeInUp(
                        delay: Duration(milliseconds: 50 * index),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: AppCard(
                            child: Theme(
                              data: Theme.of(context)
                                  .copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                childrenPadding: EdgeInsets.zero,
                                initiallyExpanded: index == 0,
                                title: Text(
                                  job.jobTitle.isEmpty
                                      ? (job.jobNo.isEmpty
                                          ? 'Job #${job.id}'
                                          : job.jobNo)
                                      : job.jobTitle,
                                  style: AppType.h3
                                      .copyWith(color: AppColors.ink),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        [
                                          if (job.jobNo.isNotEmpty)
                                            job.jobNo,
                                          job.formattedDate,
                                        ].join(' · '),
                                        style: AppType.meta.copyWith(
                                          color: AppColors.inkMuted,
                                        ),
                                      ),
                                      const SizedBox(height: AppSpace.xs),
                                      Row(
                                        children: [
                                          AppStatusChip(
                                            status: job.status.isEmpty
                                                ? 'unknown'
                                                : job.status,
                                            color: _statusColor(job.status),
                                            compact: true,
                                          ),
                                          const Spacer(),
                                          Text(
                                            job.formattedGrandTotal,
                                            style: AppType.h3.copyWith(
                                              color: AppColors.mVehicles,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                children: [
                                  const SizedBox(height: AppSpace.xs),
                                  if (job.issueType != null &&
                                      job.issueType!.isNotEmpty)
                                    _metaRow('Issue', job.issueType!),
                                  if (job.workshop != null &&
                                      job.workshop!.isNotEmpty)
                                    _metaRow('Workshop', job.workshop!),
                                  if (job.performedBy != null &&
                                      job.performedBy!.isNotEmpty)
                                    _metaRow(
                                      'Performed by',
                                      job.performedBy!,
                                    ),
                                  if (job.jobType != null &&
                                      job.jobType!.isNotEmpty)
                                    _metaRow('Type', job.jobType!),
                                  const SizedBox(height: AppSpace.xs),
                                  Wrap(
                                    spacing: AppSpace.xs,
                                    runSpacing: AppSpace.xs,
                                    children: [
                                      _costChip('Parts', job.partsCost),
                                      _costChip('Labor', job.laborCost),
                                      _costChip('Other', job.otherCost),
                                      if (job.discount > 0)
                                        _costChip('Discount', job.discount),
                                      if (job.tax > 0)
                                        _costChip('Tax', job.tax),
                                    ],
                                  ),
                                  if (job.parts.isNotEmpty) ...[
                                    const SizedBox(height: AppSpace.md),
                                    Text(
                                      'Parts (${job.parts.length})',
                                      style: AppType.h3
                                          .copyWith(color: AppColors.ink),
                                    ),
                                    const SizedBox(height: AppSpace.xs),
                                    for (final part in job.parts)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: AppSpace.xs,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    part.name,
                                                    style: AppType.bodySm
                                                        .copyWith(
                                                      color: AppColors.ink,
                                                    ),
                                                  ),
                                                  Text(
                                                    [
                                                      '${part.qty}${part.unit != null && part.unit!.isNotEmpty ? ' ${part.unit}' : ''}',
                                                      moneyBdt(part.price),
                                                    ].join(' × '),
                                                    style:
                                                        AppType.micro.copyWith(
                                                      color:
                                                          AppColors.inkFaint,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Text(
                                              moneyBdt(part.totalPrice),
                                              style: AppType.bodySm.copyWith(
                                                color: AppColors.ink,
                                                fontWeight:
                                                    FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                  if (job.remarks != null &&
                                      job.remarks!.trim().isNotEmpty) ...[
                                    const SizedBox(height: AppSpace.xs),
                                    _metaRow('Remarks', job.remarks!),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: _history!.jobs.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _metaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xxs),
      child: RichText(
        text: TextSpan(
          style: AppType.meta.copyWith(color: AppColors.inkMuted),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _costChip(String label, double value) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm,
        vertical: AppSpace.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunk,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        '$label ${moneyBdt(value)}',
        style: AppType.micro.copyWith(color: AppColors.ink),
      ),
    );
  }
}
