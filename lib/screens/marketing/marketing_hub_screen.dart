import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';

import '../../models/marketing_models.dart';
import '../../models/zone_scope.dart';
import '../../services/marketing_service.dart';
import '../../services/zone_scope_service.dart';
import '../../widgets/ui/ui.dart';
import 'followup_form_screen.dart';
import 'market_detail_screen.dart';
import 'market_form_screen.dart';
import 'market_list_screen.dart';
import 'party_detail_screen.dart';
import 'party_form_screen.dart';
import 'party_list_screen.dart';

class MarketingHubScreen extends StatefulWidget {
  const MarketingHubScreen({super.key});

  @override
  State<MarketingHubScreen> createState() => _MarketingHubScreenState();
}

class _MarketingHubScreenState extends State<MarketingHubScreen> {
  static const _previewLimit = 5;

  final MarketingService _service = MarketingService();

  bool _loadingFeature = true;
  bool _enabled = true;
  bool _loadingPreviews = false;

  /// The employee's assigned zones, resolved from the HRM profile against the
  /// Sales zone master. Null when they hold no zones or the master is
  /// unreachable, in which case every list stays unfiltered.
  ZoneScope? _scope;

  List<Party> _farms = const [];
  List<Party> _dealers = const [];
  List<Market> _markets = const [];
  String? _farmsError;
  String? _dealersError;
  String? _marketsError;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final enabled = await _service.isMarketingEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _loadingFeature = false;
    });
    if (enabled) {
      await _loadPreviews();
    }
  }

  Future<void> _loadPreviews() async {
    setState(() {
      _loadingPreviews = true;
      _farmsError = null;
      _dealersError = null;
      _marketsError = null;
    });

    _scope = await ZoneScopeService.instance.load();
    final scope = _scope;
    // Parties have no district of their own, so their zone comes from the
    // market they sit in.
    final marketDistricts = await ZoneScopeService.instance.loadMarketDistricts();

    // Master lists are company-wide (omit employee_id) and fetched unfiltered,
    // then narrowed to the employee's zones here. Filtering before the limit
    // matters: a server-side `zone_id` would both drop every record created
    // before zone tagging (zone_id NULL) and take the first N rows from other
    // zones, leaving nothing to show.
    final farmsFuture = _service.listParties(partyType: 'farm');
    final dealersFuture = _service.listParties(partyType: 'dealer');
    final marketsFuture = _service.listMarkets();

    final farmsResult = await farmsFuture;
    final dealersResult = await dealersFuture;
    final marketsResult = await marketsFuture;

    if (!mounted) return;

    List<Party> inScope(List<Party> parties) {
      if (scope == null || scope.isEmpty) {
        return parties.take(_previewLimit).toList();
      }
      return parties
          .where((p) => scope.matches(
                zoneId: p.zoneId,
                zoneName: p.zoneName,
                district: p.marketId == null
                    ? null
                    : marketDistricts[p.marketId],
              ))
          .take(_previewLimit)
          .toList();
    }

    setState(() {
      _loadingPreviews = false;
      if (farmsResult.success) {
        _farms = inScope(farmsResult.data ?? const []);
      } else {
        _farms = const [];
        _farmsError = farmsResult.message ?? 'Could not load farms.';
      }
      if (dealersResult.success) {
        _dealers = inScope(dealersResult.data ?? const []);
      } else {
        _dealers = const [];
        _dealersError = dealersResult.message ?? 'Could not load dealers.';
      }
      if (marketsResult.success) {
        final markets = marketsResult.data ?? const [];
        _markets = (scope == null || scope.isEmpty)
            ? markets.take(_previewLimit).toList()
            : markets
                .where((m) => scope.matches(
                      zoneId: m.zoneId,
                      zoneName: m.zoneName,
                      district: m.district,
                    ))
                .take(_previewLimit)
                .toList();
      } else {
        _markets = const [];
        _marketsError = marketsResult.message ?? 'Could not load markets.';
      }
    });
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (!mounted || !_enabled) return;
    _loadPreviews();
  }

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
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: RefreshIndicator(
        onRefresh: _enabled ? _loadPreviews : _init,
        color: AppColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            const SliverToBoxAdapter(
              child: AppHeader(
                title: 'Farms, Dealers and Markets',
                subtitle: 'Recent records, create, or view all',
              ),
            ),
            if (_loadingFeature)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (!_enabled)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: AppEmptyState(
                      icon: AppIcons.farms,
                      title: 'Farms, Dealers and Markets disabled',
                      subtitle:
                          'Ask an admin to enable marketing.enabled in mobile app settings.',
                      onRetry: _init,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.md, AppSpace.gutter, AppSpace.xl),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (_scope != null && !_scope!.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ZoneScopeNote(scope: _scope!),
                      ),
                    FadeInUp(
                      delay: const Duration(milliseconds: 40),
                      child: _HubGroupCard(
                        icon: AppIcons.farms,
                        label: 'Farms',
                        color: AppColors.accent,
                        createTooltip: 'Create farm',
                        viewTooltip: 'View all farms',
                        loading: _loadingPreviews,
                        error: _farmsError,
                        onRetry: _loadPreviews,
                        onCreate: () => _open(
                          const PartyFormScreen(initialPartyType: 'farm'),
                        ),
                        onView: () => _open(
                          const PartyListScreen(initialPartyType: 'farm'),
                        ),
                        child: _PartyPreviewList(
                          parties: _farms,
                          color: AppColors.accent,
                          statusColor: _statusColor,
                          onTap: (party) => _open(
                            PartyDetailScreen(
                              partyId: party.id,
                              initialParty: party,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FadeInUp(
                      delay: const Duration(milliseconds: 80),
                      child: _HubGroupCard(
                        icon: AppIcons.store,
                        label: 'Dealers',
                        color: AppColors.primary,
                        createTooltip: 'Create dealer',
                        viewTooltip: 'View all dealers',
                        loading: _loadingPreviews,
                        error: _dealersError,
                        onRetry: _loadPreviews,
                        onCreate: () => _open(
                          const PartyFormScreen(initialPartyType: 'dealer'),
                        ),
                        onView: () => _open(
                          const PartyListScreen(initialPartyType: 'dealer'),
                        ),
                        child: _PartyPreviewList(
                          parties: _dealers,
                          color: AppColors.primary,
                          statusColor: _statusColor,
                          onTap: (party) => _open(
                            PartyDetailScreen(
                              partyId: party.id,
                              initialParty: party,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FadeInUp(
                      delay: const Duration(milliseconds: 120),
                      child: _HubGroupCard(
                        icon: AppIcons.store,
                        label: 'Markets',
                        color: AppColors.secondary,
                        createTooltip: 'Create market',
                        viewTooltip: 'View all markets',
                        loading: _loadingPreviews,
                        error: _marketsError,
                        onRetry: _loadPreviews,
                        onCreate: () => _open(const MarketFormScreen()),
                        onView: () => _open(const MarketListScreen()),
                        child: _MarketPreviewList(
                          markets: _markets,
                          onTap: (market) => _open(
                            MarketDetailScreen(market: market),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FadeInUp(
                      delay: const Duration(milliseconds: 160),
                      // The untyped `push` is deliberate: the screen is
                      // pre-built and the result is discarded.
                      child: AppCard(
                        onTap: () => _open(
                          const FollowupFormScreen(showListMode: true),
                        ),
                        padding: const EdgeInsets.all(AppSpace.sm + 2),
                        child: Row(
                          children: [
                            AppIconTile(
                              icon: AppIcons.note,
                              color: AppColors.warning,
                              semanticLabel: 'Follow-ups',
                            ),
                            const SizedBox(width: AppSpace.sm + 2),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Follow-ups',
                                    style: AppType.h3
                                        .copyWith(color: AppColors.ink),
                                  ),
                                  Text(
                                    'Tasks and reminders',
                                    style: AppType.meta
                                        .copyWith(color: AppColors.inkMuted),
                                  ),
                                ],
                              ),
                            ),
                            AppIcon(
                              AppIcons.chevron,
                              size: 18,
                              color: AppColors.inkFaint,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Read-only strip naming the zones every list on this screen is scoped to, so
/// a short list reads as "Zone A has three markets" rather than a mystery.
class _ZoneScopeNote extends StatelessWidget {
  const _ZoneScopeNote({required this.scope});

  final ZoneScope scope;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.map_outlined, size: 18, color: AppColors.primary),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Showing ${scope.label}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (scope.districtNames.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    scope.districtSummary,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HubGroupCard extends StatelessWidget {
  const _HubGroupCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.createTooltip,
    required this.viewTooltip,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onCreate,
    required this.onView,
    required this.child,
  });

  final IconData icon;
  final String label;
  final Color color;
  final String createTooltip;
  final String viewTooltip;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onCreate;
  final VoidCallback onView;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // A tinted panel with a coloured left rail, one per master list. Status
    // tints this instead of dominating it, so the rail carries the module.
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border(
          left: BorderSide(color: color, width: 4),
        ),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.all(AppSpace.sm + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: AppType.h3.copyWith(fontWeight: FontWeight.w600, color: color),
                ),
              ),
              _HubIconAction(
                tooltip: createTooltip,
                icon: Icons.add_rounded,
                color: color,
                onTap: onCreate,
              ),
              const SizedBox(width: 4),
              _HubIconAction(
                tooltip: viewTooltip,
                icon: Icons.list_alt_outlined,
                color: color,
                onTap: onView,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      error!,
                      style: AppType.meta.copyWith(color: AppColors.error),
                    ),
                  ),
                  TextButton(onPressed: onRetry, child: const Text('Retry')),
                ],
              ),
            )
          else
            child,
        ],
      ),
    );
  }
}

class _HubIconAction extends StatelessWidget {
  const _HubIconAction({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, color: color, size: 20),
          ),
        ),
      ),
    );
  }
}

class _PartyPreviewList extends StatelessWidget {
  const _PartyPreviewList({
    required this.parties,
    required this.color,
    required this.statusColor,
    required this.onTap,
  });

  final List<Party> parties;
  final Color color;
  final Color Function(String?) statusColor;
  final ValueChanged<Party> onTap;

  @override
  Widget build(BuildContext context) {
    if (parties.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'No records yet — tap + to create',
          style: AppType.meta.copyWith(color: AppColors.inkMuted),
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < parties.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          InkWell(
            onTap: () => onTap(parties[i]),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  AppIcon(
                    parties[i].isFarm
                        ? AppIcons.farms
                        : AppIcons.store,
                    size: 18,
                    color: color,
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          parties[i].displayName,
                          style: AppType.bodySm.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (parties[i].phone != null ||
                            parties[i].marketName != null)
                          Text(
                            [
                              if (parties[i].phone != null) parties[i].phone!,
                              if (parties[i].marketName != null)
                                parties[i].marketName!,
                            ].join(' · '),
                            style: AppType.micro.copyWith(color: AppColors.inkMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (parties[i].status != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor(parties[i].status)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        parties[i].status!,
                        style: AppType.micro.copyWith(
                          fontWeight: FontWeight.w600,
                          color: statusColor(parties[i].status),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  AppIcon(
                    AppIcons.chevron,
                    size: 18,
                    color: AppColors.inkFaint,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MarketPreviewList extends StatelessWidget {
  const _MarketPreviewList({
    required this.markets,
    required this.onTap,
  });

  final List<Market> markets;
  final ValueChanged<Market> onTap;

  @override
  Widget build(BuildContext context) {
    if (markets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'No records yet — tap + to create',
          style: AppType.meta.copyWith(color: AppColors.inkMuted),
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < markets.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          InkWell(
            onTap: () => onTap(markets[i]),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  AppIcon(
                    AppIcons.store,
                    size: 18,
                    color: AppColors.secondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          markets[i].displayName,
                          style: AppType.bodySm.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (markets[i].locationLine.isNotEmpty)
                          Text(
                            markets[i].locationLine,
                            style: AppType.micro.copyWith(color: AppColors.inkMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  AppIcon(
                    AppIcons.chevron,
                    size: 18,
                    color: AppColors.inkFaint,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
