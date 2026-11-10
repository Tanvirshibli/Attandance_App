import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';

import '../../models/marketing_models.dart';
import '../../models/zone_scope.dart';
import '../../services/marketing_service.dart';
import '../../services/zone_scope_service.dart';
import '../../utils/marketing_filters.dart';
import '../../widgets/marketing_filter_bar.dart';
import '../../widgets/marketing_photo_widgets.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/voice_input_field.dart';
import 'party_detail_screen.dart';

class PartyListScreen extends StatefulWidget {
  const PartyListScreen({
    super.key,
    this.initialPartyType,
    this.marketId,
  });

  final String? initialPartyType;
  final int? marketId;

  @override
  State<PartyListScreen> createState() => _PartyListScreenState();
}

class _PartyListScreenState extends State<PartyListScreen> {
  final MarketingService _service = MarketingService();
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Party> _parties = const [];
  MarketingFilters _filters = const MarketingFilters();
  ZoneScope? _scope;

  static const _typeOptions = ['All', 'dealer', 'farm', 'farmer', 'outlet', 'prospect'];
  static const _statusOptions = ['All', 'active', 'inactive', 'prospect'];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPartyType?.toLowerCase();
    // The Farms / Dealers entry points lock the type, so it seeds the filter
    // instead of being offered as a dimension.
    _filters = MarketingFilters(
      type: (initial != null && _typeOptions.contains(initial))
          ? initial
          : 'All',
    );
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // Master lists are company-wide (omit employee_id); the employee's zones
    // narrow them below. Fetched unfiltered so markets, parties and visits
    // created before zone tagging (zone_id NULL) survive via the district
    // fallback, and so every assigned zone lands in one union.
    _scope = await ZoneScopeService.instance.load();
    final scope = _scope;
    // Parties have no district of their own, so their zone comes from the
    // market they sit in.
    final marketDistricts = await ZoneScopeService.instance.loadMarketDistricts();
    final result = await _service.listParties(
      partyType: _filters.type == 'All' ? null : _filters.type,
      q: _searchController.text,
      status: _filters.status,
      marketId: widget.marketId,
    );

    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _parties = const [];
        _error = result.message == 'feature_disabled'
            ? 'Farm & Dealer module is disabled.'
            : (result.message ?? 'Could not load parties.');
        _loading = false;
      });
      return;
    }

    // The area pill compares against the market's district, which the query
    // cannot express, so the remaining dimensions narrow here too.
    final List<Party> inScope = scope == null || scope.isEmpty
        ? (result.data ?? const [])
        : (result.data ?? const [])
            .where((p) => scope.matches(
                  zoneId: p.zoneId,
                  zoneName: p.zoneName,
                  district: p.marketId == null
                      ? null
                      : marketDistricts[p.marketId],
                ))
            .toList();

    setState(() {
      _parties = inScope
          .where((p) =>
              marketingStatusMatches(p.status, _filters.status) &&
              marketingTypeMatches(p.partyType, _filters.type) &&
              marketingAreaMatches(
                zoneId: p.zoneId,
                zoneName: p.zoneName,
                district:
                    p.marketId == null ? null : marketDistricts[p.marketId],
                area: _filters.area,
              ))
          .toList();
      _loading = false;
    });
  }

  /// Applies [next] and refetches, carrying a locked party type through a
  /// clear — the bar does not offer that dimension, so it must not widen.
  void _applyFilters(MarketingFilters next) {
    final locked = widget.initialPartyType != null;
    setState(() {
      _filters = locked ? next.copyWith(type: _filters.type) : next;
    });
    _load();
  }

  /// The bar's view of the filters. A locked type is not a choice the user
  /// made, so it stays out of the pill, the active count and the empty state.
  MarketingFilters get _barFilters => widget.initialPartyType == null
      ? _filters
      : _filters.copyWith(type: 'All');

  Color _statusColor(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'active':
        return AppColors.success;
      case 'inactive':
        return AppColors.error;
      case 'prospect':
        return AppColors.warning;
      default:
        return AppColors.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.initialPartyType == 'dealer'
        ? 'Dealers'
        : widget.initialPartyType == 'farm'
            ? 'Farms'
            : 'Parties';

    final lockType = widget.initialPartyType != null;
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
                title: title,
                subtitle: 'Search & filter field parties',
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.md, AppSpace.gutter, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _searchController,
                      onSubmitted: (_) => _load(),
                      decoration: InputDecoration(
                        hintText: 'Search name, phone, code…',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            VoiceMicButton(controller: _searchController),
                            IconButton(
                              icon: const Icon(Icons.arrow_forward_rounded),
                              onPressed: _load,
                            ),
                          ],
                        ),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    MarketingFilterBar(
                      filters: _barFilters,
                      dimensions: [
                        MarketingFilterDimension.status,
                        if (!lockType) MarketingFilterDimension.type,
                        MarketingFilterDimension.area,
                      ],
                      options: {
                        MarketingFilterDimension.status: _statusOptions,
                        MarketingFilterDimension.type: _typeOptions,
                        MarketingFilterDimension.area:
                            marketingAreaOptions(_scope),
                      },
                      onChanged: _applyFilters,
                    ),
                  ],
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
                      title: 'Could not load',
                      subtitle: _error,
                      onRetry: _load,
                    ),
                  ),
                ),
              )
            else if (_parties.isEmpty)
              SliverFillRemaining(
                // The clear action makes the column taller than the viewport on
                // short screens, so let the sliver grow with it.
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppEmptyState(
                          icon: Icons.storefront_outlined,
                          title: 'No parties found',
                          subtitle: _barFilters.isActive
                              ? 'No parties match these filters.'
                              : (_scope == null || _scope!.isEmpty
                                  ? 'Create a dealer or farm to get started.'
                                  : 'No dealers or farms in ${_scope!.label} yet.'),
                          // Retrying would only repeat the same query, so the
                          // filtered dead end offers the way out instead.
                          onRetry: _barFilters.isActive ? null : _load,
                        ),
                        if (_barFilters.isActive)
                          AppButton(
                            label: 'Clear filters',
                            icon: Icons.close_rounded,
                            kind: AppButtonKind.secondary,
                            expand: false,
                            onPressed: () => _applyFilters(_filters.cleared),
                          ),
                      ],
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
                      final party = _parties[index];
                      return FadeInUp(
                        delay: Duration(milliseconds: 30 * index),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: AppCard(
                            padding: EdgeInsets.zero,
                            child: InkWell(
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        PartyDetailScreen(partyId: party.id),
                                  ),
                                );
                                _load();
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: [
                                    if (marketingPhotoUrls(party.attachments)
                                        .isNotEmpty)
                                      MarketingThumb(
                                        attachments: party.attachments,
                                        size: 48,
                                      )
                                    else
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: (party.isFarm
                                                  ? AppColors.accent
                                                  : AppColors.primary)
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                        child: Icon(
                                          party.isFarm
                                              ? Icons.agriculture_outlined
                                              : Icons.storefront_outlined,
                                          color: party.isFarm
                                              ? AppColors.accent
                                              : AppColors.primary,
                                        ),
                                      ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            party.displayName,
                                            style: AppType.body.copyWith(fontWeight: FontWeight.w600),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            [
                                              party.partyType,
                                              if (party.phone != null)
                                                party.phone!,
                                              if (party.marketName != null)
                                                party.marketName!,
                                            ].join(' · '),
                                            style: AppType.micro.copyWith(color: AppColors.inkMuted),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _statusColor(party.status)
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        party.status ?? '—',
                                        style: AppType.micro.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: _statusColor(party.status),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: _parties.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
