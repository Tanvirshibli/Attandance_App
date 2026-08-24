import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/theme.dart';
import '../../models/marketing_models.dart';
import '../../services/marketing_service.dart';
import '../../widgets/api_empty_state.dart';
import '../../widgets/gradient_screen_header.dart';
import '../../widgets/marketing_photo_widgets.dart';
import '../../widgets/section_card.dart';
import 'visit_form_shared.dart';

class VisitDetailScreen extends StatefulWidget {
  const VisitDetailScreen({
    super.key,
    required this.visitId,
    this.initial,
  });

  final int visitId;
  final Visit? initial;

  @override
  State<VisitDetailScreen> createState() => _VisitDetailScreenState();
}

class _VisitDetailScreenState extends State<VisitDetailScreen> {
  final MarketingService _service = MarketingService();
  Visit? _visit;
  List<Attachment> _attachments = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _visit = widget.initial;
    _attachments = widget.initial?.attachments ?? const [];
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _service.getVisit(widget.visitId);
    if (!mounted) return;
    if (!result.success || result.data == null) {
      setState(() {
        _error = result.message ?? 'Could not load visit.';
        _loading = false;
      });
      return;
    }
    var visit = result.data!;
    var attachments = visit.attachments;
    if (attachments.isEmpty) {
      final listed = await _service.listAttachments(
        attachableType: 'visit',
        attachableId: visit.id,
      );
      if (listed.success && listed.data != null) {
        attachments = listed.data!;
      }
    }
    if (!mounted) return;
    setState(() {
      _visit = visit;
      _attachments = attachments;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final visit = _visit;
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
                title: 'Visit details',
                subtitle: visit?.displayName ?? 'Loading…',
              ),
            ),
            if (_loading && visit == null)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && visit == null)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ApiEmptyState(
                      icon: Icons.error_outline,
                      title: 'Could not load',
                      subtitle: _error,
                      onRetry: _load,
                    ),
                  ),
                ),
              )
            else if (visit != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                sliver: SliverToBoxAdapter(
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _row('Date', visit.visitDate),
                        _row(
                          'Visit type',
                          visit.visitType != null
                              ? displayVisitType(visit.visitType!)
                              : null,
                        ),
                        _row('Party', visit.partyName),
                        _row('Status', visit.status),
                        _row('Objective', visit.objective ?? visit.purpose),
                        _row('Findings', visit.findings),
                        _row('Result', visit.result ?? visit.outcome),
                        _row('Next plan', visit.nextPlan),
                        _row('Next visit', visit.nextVisitDate),
                        _row('Order amount', _n(visit.orderAmount)),
                        _row('Collection amount', _n(visit.collectionAmount)),
                        _row('Notes', visit.notes),
                        if (visit.products.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Product observations',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ...visit.products.map(
                            (p) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                [
                                  p.productName.isNotEmpty
                                      ? p.productName
                                      : 'Product',
                                  if (p.observationType != null)
                                    p.observationType!,
                                  if (p.stockQuantity != null)
                                    'stock ${p.stockQuantity}',
                                  if (p.demandQuantity != null)
                                    'demand ${p.demandQuantity}',
                                  if (p.orderQty != null)
                                    'order ${p.orderQty}',
                                ].join(' · '),
                                style: GoogleFonts.poppins(fontSize: 13),
                              ),
                            ),
                          ),
                        ],
                        MarketingPhotoGrid(attachments: _attachments),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String? _n(num? v) => v?.toString();

  Widget _row(String label, String? value) {
    if (value == null || value.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
