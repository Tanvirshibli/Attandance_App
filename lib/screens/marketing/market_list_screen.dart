import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';

import '../../models/marketing_models.dart';
import '../../models/zone_scope.dart';
import '../../services/marketing_service.dart';
import '../../services/zone_scope_service.dart';
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
  ZoneScope? _scope;

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
            else if (_markets.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: AppEmptyState(
                      icon: Icons.store_mall_directory_outlined,
                      title: 'No markets yet',
                      subtitle: _scope == null || _scope!.isEmpty
                          ? 'Create a market to assign dealers and farms.'
                          : 'No markets in ${_scope!.label} yet.',
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
                      final m = _markets[index];
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
                                    Text(
                                      m.displayName,
                                      style: AppType.h3.copyWith(fontWeight: FontWeight.w600),
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
                    childCount: _markets.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
