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
import 'market_detail_screen.dart';

class MarketListScreen extends StatefulWidget {
  const MarketListScreen({super.key});

  @override
  State<MarketListScreen> createState() => _MarketListScreenState();
}

class _MarketListScreenState extends State<MarketListScreen> {
  final MarketingService _service = MarketingService();
  final TextEditingController _search = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Market> _markets = const [];
  MarketingFilters _filters = const MarketingFilters();
  ZoneScope? _scope;

  static const _statusOptions = ['All', 'active', 'inactive'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _scope = await ZoneScopeService.instance.load();
    // Fetched unfiltered and narrowed here: `zone_id` in the query can only
    // return rows explicitly tagged with a zone, and every market created
    // before zone tagging carries NULL. Filtering in Dart keeps those in
    // scope via the district fallback, and unions every assigned zone.
    final result = await _service.listMarkets(q: _search.text);
    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _markets = const [];
        _error = result.message == 'feature_disabled'
            ? 'Farm & Dealer module is disabled.'
            : (result.message ?? 'Could not load markets.');
        _loading = false;
      });
      return;
    }
    final scope = _scope;
    setState(() {
      _markets = scope == null || scope.isEmpty
          ? (result.data ?? const [])
          : (result.data ?? const [])
              .where((m) => scope.matches(
                    zoneId: m.zoneId,
                    zoneName: m.zoneName,
                    district: m.district,
                  ))
              .toList();
      _loading = false;
    });
  }

  /// The rows the bar lets through. Client-side because the fetch is already
  /// unfiltered for the zone-scope reason above.
  List<Market> get _visible => _markets
      .where((m) =>
          marketingStatusMatches(m.status, _filters.status) &&
          marketingTypeListMatches(m.productTypes, _filters.type) &&
          marketingAreaMatches(
            zoneId: m.zoneId,
            zoneName: m.zoneName,
            district: m.district,
            area: _filters.area,
          ))
      .toList();

  /// Product types actually present in the loaded markets — a pill offering a
  /// type nobody carries would only ever empty the list.
  List<String> get _typeOptions {
    final types = <String>{};
    for (final market in _markets) {
      for (final type in market.productTypes) {
        final value = type.trim();
        if (value.isNotEmpty) types.add(value);
      }
    }
    final sorted = types.toList()..sort();
    return ['All', ...sorted];
  }

  @override
  Widget build(BuildContext context) {
    final markets = _visible;
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
                title: 'Markets',
                subtitle: 'Bazaars & coverage areas',
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.md, AppSpace.gutter, 0),
                child: TextField(
                  controller: _search,
                  onSubmitted: (_) => _load(),
                  decoration: InputDecoration(
                    hintText: 'Search markets',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        VoiceMicButton(controller: _search),
                        IconButton(
                          onPressed: _load,
                          icon: const Icon(Icons.arrow_forward),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.sm, AppSpace.gutter, 0),
                child: MarketingFilterBar(
                  filters: _filters,
                  dimensions: const [
                    MarketingFilterDimension.status,
                    MarketingFilterDimension.type,
                    MarketingFilterDimension.area,
                  ],
                  options: {
                    MarketingFilterDimension.status: _statusOptions,
                    MarketingFilterDimension.type: _typeOptions,
                    MarketingFilterDimension.area:
                        marketingAreaOptions(_scope),
                  },
                  onChanged: (f) => setState(() => _filters = f),
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
            else if (markets.isEmpty)
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
                        if (_filters.isActive && _markets.isNotEmpty)
                          const AppEmptyState(
                            icon: Icons.filter_alt_off_outlined,
                            title: 'No markets match',
                            subtitle: 'Clear the filters to see every market again.',
                          )
                        else
                          AppEmptyState(
                            icon: Icons.store_mall_directory_outlined,
                            title: 'No markets yet',
                            subtitle: _scope == null || _scope!.isEmpty
                                ? 'Create a market to assign dealers and farms.'
                                : 'No markets in ${_scope!.label} yet.',
                          ),
                        // This state has no retry on purpose; a filtered dead
                        // end still needs a way out.
                        if (_filters.isActive)
                          AppButton(
                            label: 'Clear filters',
                            icon: Icons.close_rounded,
                            kind: AppButtonKind.secondary,
                            expand: false,
                            onPressed: () =>
                                setState(() => _filters = _filters.cleared),
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
                      final m = markets[index];
                      final loc = m.locationLine;
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
                                        MarketDetailScreen(market: m),
                                  ),
                                );
                                _load();
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (marketingPhotoUrls(m.attachments)
                                            .isNotEmpty) ...[
                                          MarketingThumb(
                                            attachments: m.attachments,
                                            size: 56,
                                            radius: 16,
                                          ),
                                          const SizedBox(width: 12),
                                        ],
                                        Expanded(
                                          child: Text(
                                            m.displayName,
                                            style: AppType.h3.copyWith(fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (loc.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        loc,
                                        style: AppType.meta.copyWith(color: AppColors.inkMuted),
                                      ),
                                    ],
                                    if (m.status != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        m.status!,
                                        style: AppType.micro.copyWith(fontWeight: FontWeight.w500, color: AppColors.info),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: markets.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
