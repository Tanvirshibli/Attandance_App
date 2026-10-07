import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';

import '../../models/marketing_models.dart';
import '../../services/marketing_service.dart';
import '../../widgets/marketing_photo_widgets.dart';
import '../../widgets/ui/ui.dart';
import 'market_form_screen.dart';
import 'party_detail_screen.dart';

/// Market record page — shows market intel (survey data) plus the parties
/// attached to this market. Markets are edited in place by field users;
/// there is no separate "market visit" flow.
class MarketDetailScreen extends StatefulWidget {
  const MarketDetailScreen({super.key, required this.market});

  final Market market;

  @override
  State<MarketDetailScreen> createState() => _MarketDetailScreenState();
}

class _MarketDetailScreenState extends State<MarketDetailScreen> {
  final MarketingService _service = MarketingService();
  late Market _market;
  bool _loading = true;
  String? _error;
  List<Party> _parties = const [];

  @override
  void initState() {
    super.initState();
    _market = widget.market;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // Parties under a market are company-wide (omit employee_id).
    final result = await _service.listParties(
      marketId: _market.id,
    );
    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _parties = const [];
        _error = result.message ?? 'Could not load parties.';
        _loading = false;
      });
      return;
    }
    setState(() {
      _parties = result.data ?? const [];
      _loading = false;
    });
  }

  Future<void> _editMarket() async {
    final updated = await Navigator.of(context).push<Market>(
      MaterialPageRoute(
        builder: (_) => MarketFormScreen(market: _market),
      ),
    );
    if (!mounted) return;
    if (updated != null) {
      setState(() => _market = updated);
    }
    _load();
  }

  Widget _intelChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$label: $value',
        style: AppType.meta.copyWith(color: AppColors.ink),
      ),
    );
  }

  Widget _intelSection(Market m) {
    final hasAny = m.feedSharePercent != null ||
        m.chicksSharePercent != null ||
        m.productTypes.isNotEmpty ||
        m.feedDealerCount != null ||
        m.chicksDealerCount != null ||
        m.broilerFarmCount != null ||
        m.layerFarmCount != null ||
        m.colorFarmCount != null ||
        m.cockFarmCount != null ||
        m.competitorCompanies.isNotEmpty;
    if (!hasAny) {
      return Text(
        'No market survey data yet — tap Edit to fill it in.',
        style: AppType.meta.copyWith(color: AppColors.inkFaint),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (m.feedSharePercent != null)
              _intelChip('Feed share', '${m.feedSharePercent}%'),
            if (m.chicksSharePercent != null)
              _intelChip('Chicks share', '${m.chicksSharePercent}%'),
            if (m.feedDealerCount != null)
              _intelChip('Feed dealers', '${m.feedDealerCount}'),
            if (m.chicksDealerCount != null)
              _intelChip('Chicks dealers', '${m.chicksDealerCount}'),
            if (m.broilerFarmCount != null)
              _intelChip('Broiler farms', '${m.broilerFarmCount}'),
            if (m.layerFarmCount != null)
              _intelChip('Layer farms', '${m.layerFarmCount}'),
            if (m.colorFarmCount != null)
              _intelChip('Color farms', '${m.colorFarmCount}'),
            if (m.cockFarmCount != null)
              _intelChip('Cock farms', '${m.cockFarmCount}'),
          ],
        ),
        if (m.productTypes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: m.productTypes
                .map(
                  (t) => Chip(
                    label: Text(t, style: AppType.micro),
                    visualDensity: VisualDensity.compact,
                  ),
                )
                .toList(),
          ),
        ],
        if (m.competitorCompanies.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Competitor companies',
            style: AppType.bodySm.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
          ),
          const SizedBox(height: 6),
          ...m.competitorCompanies.map(
            (c) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.factory_outlined, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      [
                        c.name,
                        if (c.sharePercent != null) '${c.sharePercent}%',
                        if (c.note != null && c.note!.isNotEmpty) '· ${c.note}',
                      ].join(' — '),
                      style: AppType.meta,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final market = _market;
    final loc = market.locationLine;
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
                title: market.displayName,
                subtitle: loc.isNotEmpty ? loc : 'Market survey',
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.md, AppSpace.gutter, AppSpace.xs),
              sliver: SliverToBoxAdapter(
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (market.address != null)
                                  Text(
                                    market.address!,
                                    style:
                                        AppType.bodySm,
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  [
                                    if (market.zoneName != null)
                                      'Zone ${market.zoneName}',
                                    if (market.status != null) market.status!,
                                  ].join(' · '),
                                  style: AppType.meta.copyWith(fontWeight: FontWeight.w500, color: AppColors.info),
                                ),
                              ],
                            ),
                          ),
                          IconButton.filled(
                            onPressed: _editMarket,
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            tooltip: 'Edit market survey',
                            style: IconButton.styleFrom(
                              backgroundColor: AppColors.secondary,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _intelSection(market),
                      // The photos uploaded with the market survey.
                      if (marketingPhotoUrls(market.attachments).isNotEmpty)
                        MarketingPhotoGrid(attachments: market.attachments),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.xxs, AppSpace.gutter, 0),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'Parties in this market',
                  style: AppType.body.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
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
              const SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpace.lg),
                    child: AppEmptyState(
                      icon: Icons.storefront_outlined,
                      title: 'No parties in this market',
                      subtitle: 'Create a dealer or farm and assign this market.',
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.xs, AppSpace.gutter, AppSpace.xl),
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
                            child: ListTile(
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        PartyDetailScreen(partyId: party.id),
                                  ),
                                );
                                _load();
                              },
                              leading: marketingPhotoUrls(party.attachments)
                                      .isEmpty
                                  ? Icon(
                                      party.isFarm
                                          ? Icons.agriculture_outlined
                                          : Icons.storefront_outlined,
                                      color: party.isFarm
                                          ? AppColors.accent
                                          : AppColors.primary,
                                    )
                                  : MarketingThumb(
                                      attachments: party.attachments,
                                      size: 44,
                                    ),
                              title: Text(
                                party.displayName,
                                style: AppType.body.copyWith(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                [
                                  party.partyType,
                                  if (party.phone != null) party.phone!,
                                ].join(' · '),
                                style: AppType.meta,
                              ),
                              trailing: const Icon(Icons.chevron_right),
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
