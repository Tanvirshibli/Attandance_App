import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/theme.dart';
import '../../models/marketing_models.dart';
import '../../services/auth_service.dart';
import '../../services/marketing_service.dart';
import '../../widgets/api_empty_state.dart';
import '../../widgets/filter_chip_row.dart';
import '../../widgets/gradient_screen_header.dart';
import '../../widgets/section_card.dart';

class VisitListScreen extends StatefulWidget {
  const VisitListScreen({super.key, this.partyId});

  final int? partyId;

  @override
  State<VisitListScreen> createState() => _VisitListScreenState();
}

class _VisitListScreenState extends State<VisitListScreen> {
  final MarketingService _service = MarketingService();
  final AuthService _authService = AuthService();

  bool _loading = true;
  String? _error;
  List<Visit> _visits = const [];
  String _statusFilter = 'All';

  static const _statusOptions = [
    'All',
    'draft',
    'in_progress',
    'completed',
    'cancelled',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final profile = await _authService.getCurrentUserProfile();
    final result = await _service.listVisits(
      employeeId: profile?.canonicalEmployeeId,
      partyId: widget.partyId,
      status: _statusFilter,
    );
    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _visits = const [];
        _error = result.message ?? 'Could not load visits.';
        _loading = false;
      });
      return;
    }
    setState(() {
      _visits = result.data ?? const [];
      _loading = false;
    });
  }

  Color _statusColor(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'completed':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      case 'in_progress':
        return AppColors.info;
      default:
        return AppColors.warning;
    }
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
                title: 'My visits',
                subtitle: 'Visit history & outcomes',
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: FilterChipRow(
                  options: _statusOptions,
                  selected: _statusFilter,
                  onSelected: (v) {
                    setState(() => _statusFilter = v);
                    _load();
                  },
                ),
              ),
            ),
            if (_loading)
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
                      title: 'Could not load visits',
                      subtitle: _error,
                      onRetry: _load,
                    ),
                  ),
                ),
              )
            else if (_visits.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: ApiEmptyState(
                      icon: Icons.route_outlined,
                      title: 'No visits yet',
                      subtitle: 'Log visits from a dealer or farm detail page.',
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
                      final visit = _visits[index];
                      return FadeInUp(
                        delay: Duration(milliseconds: 30 * index),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: SectionCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        visit.partyName ??
                                            'Party #${visit.partyId}',
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _statusColor(visit.status)
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        visit.status ?? '—',
                                        style: GoogleFonts.poppins(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: _statusColor(visit.status),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  [
                                    if (visit.visitDate != null)
                                      visit.visitDate!,
                                    if (visit.purpose != null) visit.purpose!,
                                    if (visit.outcome != null) visit.outcome!,
                                  ].join(' · '),
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                if (visit.checkInLat != null &&
                                    visit.checkInLng != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'GPS ${visit.checkInLat!.toStringAsFixed(4)}, ${visit.checkInLng!.toStringAsFixed(4)}',
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
                    },
                    childCount: _visits.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
