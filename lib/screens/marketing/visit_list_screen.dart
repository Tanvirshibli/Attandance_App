import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';

import '../../models/marketing_models.dart';
import '../../models/zone_scope.dart';
import '../../services/auth_service.dart';
import '../../services/marketing_service.dart';
import '../../services/zone_scope_service.dart';
import '../../utils/marketing_filters.dart';
import '../../widgets/marketing_filter_bar.dart';
import '../../widgets/marketing_photo_widgets.dart';
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
  /// Zone-narrowed rows from before the bar's filters.
  ///
  /// The type pill builds its choices from these, not from [_visits]: deriving
  /// them from the narrowed list would collapse the options to the single type
  /// already chosen, leaving no way back except clearing.
  List<Visit> _scopedVisits = const [];
  // The status pill is only one of the bar's axes, so the whole filter state
  // lives here rather than in a lone status string.
  MarketingFilters _filters = const MarketingFilters();
  ZoneScope? _scope;

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
    _scope = await ZoneScopeService.instance.load();
    // `zone_id` is deliberately not sent: the visits endpoint accepts it but
    // never applies it, so it filtered nothing. Visits carry no district
    // either, so zone filtering here is on the stored zone id and name only —
    // a visit predating zone tagging (zone_id NULL) drops out.
    final result = await _service.listVisits(
      employeeId: profile?.canonicalEmployeeId,
      partyId: widget.partyId,
      status: _filters.status,
    );
    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _visits = const [];
        _scopedVisits = const [];
        _error = result.message ?? 'Could not load visits.';
        _loading = false;
      });
      return;
    }
    final scope = _scope;
    final zoneRows = scope == null || scope.isEmpty
        ? (result.data ?? const [])
        : (result.data ?? const [])
            .where((v) => scope.matches(zoneId: v.zoneId, zoneName: v.zoneName))
            .toList();
    // Only status reaches the endpoint, so type, date and area are applied on
    // what came back. Area runs on top of the zone narrowing above because an
    // officer scoped to several zones can still ask for just one of them.
    setState(() {
      _scopedVisits = zoneRows;
      _visits = zoneRows
          .where((v) =>
              marketingStatusMatches(v.status, _filters.status) &&
              marketingTypeMatches(v.visitType, _filters.type) &&
              marketingDateMatches(v.visitDate, _filters.date) &&
              marketingAreaMatches(
                zoneId: v.zoneId,
                zoneName: v.zoneName,
                area: _filters.area,
              ))
          .toList();
      _loading = false;
    });
  }

  /// The type options the officer can choose from.
  ///
  /// A visit's type is free-form on the server, so a hardcoded list would offer
  /// choices this module never writes and hide the ones it does. `All` leads;
  /// blanks and duplicates drop out; the rest sort so the order is stable.
  List<String> get _typeOptions {
    final unique = <String>{};
    for (final visit in _scopedVisits) {
      final text = (visit.visitType ?? '').trim();
      if (text.isNotEmpty) unique.add(text);
    }
    final sorted = unique.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ['All', ...sorted];
  }

  /// Nothing matched an active filter.
  ///
  /// The plain empty state reads "No visits yet", which would be a lie when the
  /// visits exist and only the filter hid them — so this one names the filter
  /// and puts the way out on screen.
  Widget _noMatchEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppEmptyState(
            icon: Icons.route_outlined,
            title: 'No visits match these filters',
            subtitle: 'Nothing here matches the current filters.',
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.lg),
            child: AppButton(
              label: 'Clear filters',
              icon: Icons.close_rounded,
              kind: AppButtonKind.secondary,
              expand: false,
              onPressed: () {
                setState(() => _filters = _filters.cleared);
                _load();
              },
            ),
          ),
        ],
      ),
    );
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
                child: MarketingFilterBar(
                  filters: _filters,
                  dimensions: const [
                    MarketingFilterDimension.status,
                    MarketingFilterDimension.type,
                    MarketingFilterDimension.date,
                    MarketingFilterDimension.area,
                  ],
                  options: {
                    MarketingFilterDimension.status: _statusOptions,
                    MarketingFilterDimension.type: _typeOptions,
                    MarketingFilterDimension.area: marketingAreaOptions(_scope),
                  },
                  onChanged: (filters) {
                    setState(() => _filters = filters);
                    // Status goes to the endpoint, so the list is refetched
                    // rather than narrowed in place.
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
            else if (_visits.isEmpty && _filters.isActive)
              SliverFillRemaining(child: _noMatchEmptyState())
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
                                    if (marketingPhotoUrls(visit.attachments)
                                        .isNotEmpty) ...[
                                      MarketingThumb(
                                        attachments: visit.attachments,
                                        size: 48,
                                        radius: 12,
                                      ),
                                      const SizedBox(width: 10),
                                    ],
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
