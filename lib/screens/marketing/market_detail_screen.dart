import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/theme.dart';
import '../../models/marketing_models.dart';
import '../../services/marketing_service.dart';
import '../../widgets/api_empty_state.dart';
import '../../widgets/gradient_screen_header.dart';
import '../../widgets/section_card.dart';
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
        style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textPrimary),
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
        style: GoogleFonts.poppins(
          fontSize: 12,
          color: AppColors.textHint,
        ),
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
                    label: Text(t, style: GoogleFonts.poppins(fontSize: 11)),
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
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
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
                      style: GoogleFonts.poppins(fontSize: 12),
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
                title: market.displayName,
                subtitle: loc.isNotEmpty ? loc : 'Market survey',
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              sliver: SliverToBoxAdapter(
                child: SectionCard(
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
                                        GoogleFonts.poppins(fontSize: 13),
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  [
                                    if (market.zoneName != null)
                                      'Zone ${market.zoneName}',
                                    if (market.status != null) market.status!,
                                  ].join(' · '),
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: AppColors.info,
                                    fontWeight: FontWeight.w500,
                                  ),
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
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'Parties in this market',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
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
            else if (_parties.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: ApiEmptyState(
                      icon: Icons.storefront_outlined,
                      title: 'No parties in this market',
                      subtitle: 'Create a dealer or farm and assign this market.',
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final party = _parties[index];
                      return FadeInUp(
                        delay: Duration(milliseconds: 30 * index),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: SectionCard(
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
                              leading: Icon(
                                party.isFarm
                                    ? Icons.agriculture_outlined
                                    : Icons.storefront_outlined,
                                color: party.isFarm
                                    ? AppColors.accent
                                    : AppColors.primary,
                              ),
                              title: Text(
                                party.displayName,
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  party.partyType,
                                  if (party.phone != null) party.phone!,
                                ].join(' · '),
                                style: GoogleFonts.poppins(fontSize: 12),
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
