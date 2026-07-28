import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import '../models/sales_models.dart' show moneyBdt;
import '../models/vehicle_models.dart';
import '../services/vehicle_service.dart';
import '../widgets/api_empty_state.dart';
import '../widgets/gradient_screen_header.dart';
import '../widgets/section_card.dart';

class VehicleDetailScreen extends StatefulWidget {
  const VehicleDetailScreen({super.key, required this.vehicle});

  final VehicleSummary vehicle;

  @override
  State<VehicleDetailScreen> createState() => _VehicleDetailScreenState();
}

class _VehicleDetailScreenState extends State<VehicleDetailScreen> {
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
                title: vehicle.displayPlate,
                subtitle: 'Maintenance history',
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vehicle.displayPlate,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Vehicle no: ${vehicle.tVehicleNo.isEmpty ? '—' : vehicle.tVehicleNo}',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        'Purchased: ${vehicle.formattedPurchaseDate}',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (_history != null)
                        Text(
                          'Jobs shown: ${_history!.total}',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: AppColors.textHint,
                          ),
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
                    child: ApiEmptyState(
                      icon: Icons.error_outline,
                      title: 'Could not load history',
                      subtitle: _error!,
                      onRetry: _load,
                    ),
                  ),
                ),
              )
            else if (_history == null || _history!.jobs.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: ApiEmptyState(
                      icon: Icons.build_outlined,
                      title: 'No maintenance jobs',
                      subtitle:
                          'Recent maintenance jobs for this vehicle will appear here.',
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final job = _history!.jobs[index];
                      return FadeInUp(
                        delay: Duration(milliseconds: 50 * index),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SectionCard(
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
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        [
                                          if (job.jobNo.isNotEmpty) job.jobNo,
                                          job.formattedDate,
                                        ].join(' · '),
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _statusColor(job.status)
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              job.status.isEmpty
                                                  ? 'unknown'
                                                  : job.status,
                                              style: GoogleFonts.poppins(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    _statusColor(job.status),
                                              ),
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            job.formattedGrandTotal,
                                            style: GoogleFonts.poppins(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                children: [
                                  const SizedBox(height: 8),
                                  if (job.issueType != null &&
                                      job.issueType!.isNotEmpty)
                                    _metaRow('Issue', job.issueType!),
                                  if (job.workshop != null &&
                                      job.workshop!.isNotEmpty)
                                    _metaRow('Workshop', job.workshop!),
                                  if (job.performedBy != null &&
                                      job.performedBy!.isNotEmpty)
                                    _metaRow('Performed by', job.performedBy!),
                                  if (job.jobType != null &&
                                      job.jobType!.isNotEmpty)
                                    _metaRow('Type', job.jobType!),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
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
                                    const SizedBox(height: 12),
                                    Text(
                                      'Parts (${job.parts.length})',
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    for (final part in job.parts)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    part.name,
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                  Text(
                                                    [
                                                      '${part.qty}${part.unit != null && part.unit!.isNotEmpty ? ' ${part.unit}' : ''}',
                                                      moneyBdt(part.price),
                                                    ].join(' × '),
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 11,
                                                      color: AppColors
                                                          .textSecondary,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Text(
                                              moneyBdt(part.totalPrice),
                                              style: GoogleFonts.poppins(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                  if (job.remarks != null &&
                                      job.remarks!.trim().isNotEmpty) ...[
                                    const SizedBox(height: 8),
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
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$label ${moneyBdt(value)}',
        style: GoogleFonts.poppins(fontSize: 11),
      ),
    );
  }
}
