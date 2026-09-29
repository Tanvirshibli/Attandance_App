import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';

import '../../models/marketing_models.dart';
import '../../services/auth_service.dart';
import '../../services/marketing_service.dart';
import '../../widgets/filter_chip_row.dart';
import '../../widgets/ui/ui.dart';

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
      zoneId: profile?.zoneId,
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
      backgroundColor: AppColors.canvas,
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            const SliverToBoxAdapter(
              child: AppHeader(
                title: 'My visits',
                subtitle: 'Visit history & outcomes',
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.md, AppSpace.gutter, 0),
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
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: AppEmptyState(
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
                    padding: EdgeInsets.all(AppSpace.lg),
                    child: AppEmptyState(
                      icon: Icons.route_outlined,
                      title: 'No visits yet',
                      subtitle: 'Log visits from a dealer or farm detail page.',
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
                      final visit = _visits[index];
                      return FadeInUp(
                        delay: Duration(milliseconds: 30 * index),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: AppCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        visit.partyName ??
                                            'Party #${visit.partyId}',
                                        style: AppType.body.copyWith(fontWeight: FontWeight.w600),
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
                                        style: AppType.micro.copyWith(
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
                                  style: AppType.meta.copyWith(color: AppColors.inkMuted),
                                ),
                                if (visit.checkInLat != null &&
                                    visit.checkInLng != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'GPS ${visit.checkInLat!.toStringAsFixed(4)}, ${visit.checkInLng!.toStringAsFixed(4)}',
                                    style: AppType.micro.copyWith(color: AppColors.inkFaint),
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
