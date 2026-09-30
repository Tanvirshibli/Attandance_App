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

/// Farms, Dealers and Markets.
///
/// One full-screen grid per tab, with the active tab's Create / View-all actions
/// pinned to the bottom so the grid gets every remaining pixel. The page itself
/// does not scroll — each grid does — which is why the body is a plain `Column`
/// rather than a `CustomScrollView`.
class MarketingHubScreen extends StatefulWidget {
  const MarketingHubScreen({super.key});

  @override
  State<MarketingHubScreen> createState() => _MarketingHubScreenState();
}

class _MarketingHubScreenState extends State<MarketingHubScreen>
    with SingleTickerProviderStateMixin {
  final MarketingService _service = MarketingService();

  /// The API caps `limit` at 500 and defaults to 100. A grid is only worth
  /// having with more rows than that, and the lists are narrowed to the
  /// employee's zones client-side afterwards — a low server-side limit would cut
  /// the visible rows, not just the page size.
  static const int _listLimit = 200;

  // Built in initState rather than as a `late final` field initializer. A lazy
  // controller would be constructed for the first time inside dispose() when a
  // screen is torn down before its first build, and the mixin would then look
  // up a TickerMode on an already deactivated element.
  late final TabController _tabController;

  bool _loadingFeature = true;
  bool _enabled = true;
  bool _loadingRecords = false;

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

  /// Create / View-all labels and colours, indexed by tab position. The action
  /// bar reads the entry for whichever tab is selected.
  static final _tabActions = <_TabAction>[
    const _TabAction('Add farm', 'All farms', AppColors.accent),
    const _TabAction('Add dealer', 'All dealers', AppColors.primary),
    const _TabAction('Add market', 'All markets', AppColors.secondary),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final enabled = await _service.isMarketingEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _loadingFeature = false;
    });
    if (enabled) {
      await _loadRecords();
    }
  }

  Future<void> _loadRecords() async {
    if (!_enabled) return;
    setState(() {
      _loadingRecords = true;
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
    // then narrowed to the employee's zones here. Filtering before any limit
    // matters: a server-side `zone_id` would both drop every record created
    // before zone tagging (zone_id NULL) and take the first N rows from other
    // zones, leaving nothing to show.
    final farmsResult = await _service.listParties(
      partyType: 'farm',
      limit: _listLimit,
    );
    final dealersResult = await _service.listParties(
      partyType: 'dealer',
      limit: _listLimit,
    );
    final marketsResult = await _service.listMarkets(limit: _listLimit);

    if (!mounted) return;

    List<Party> inScope(List<Party> parties) {
      if (scope == null || scope.isEmpty) return parties;
      return parties
          .where((p) => scope.matches(
                zoneId: p.zoneId,
                zoneName: p.zoneName,
                district: p.marketId == null
                    ? null
                    : marketDistricts[p.marketId],
              ))
          .toList();
    }

    setState(() {
      _loadingRecords = false;
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
            ? markets
            : markets
                .where((m) => scope.matches(
                      zoneId: m.zoneId,
                      zoneName: m.zoneName,
                      district: m.district,
                    ))
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
    await _loadRecords();
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

  void _createFor(int index) {
    switch (index) {
      case 0:
        _open(const PartyFormScreen(initialPartyType: 'farm'));
      case 1:
        _open(const PartyFormScreen(initialPartyType: 'dealer'));
      default:
        _open(const MarketFormScreen());
    }
  }

  void _viewAllFor(int index) {
    switch (index) {
      case 0:
        _open(const PartyListScreen(initialPartyType: 'farm'));
      case 1:
        _open(const PartyListScreen(initialPartyType: 'dealer'));
      default:
        _open(const MarketListScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Column(
        children: [
          const AppHeader(
            title: 'Farms, Dealers and Markets',
            subtitle: 'Tap a record to open it',
          ),
          if (_loadingFeature)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (!_enabled)
            Expanded(
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
          else ...[
            if (_scope != null && !_scope!.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpace.gutter, 0, AppSpace.gutter, AppSpace.md),
                child: _ZoneScopeNote(scope: _scope!),
              ),
            Container(
              color: AppColors.canvas,
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorWeight: 3,
                dividerColor: AppColors.line,
                labelStyle: AppType.bodySm.copyWith(fontWeight: FontWeight.w700),
                unselectedLabelStyle:
                    AppType.bodySm.copyWith(color: AppColors.inkMuted),
                labelColor: AppColors.ink,
                unselectedLabelColor: AppColors.inkMuted,
                tabs: [
                  Tab(icon: Icon(AppIcons.farms), text: 'Farms'),
                  Tab(icon: Icon(AppIcons.store), text: 'Dealers'),
                  Tab(icon: Icon(AppIcons.store), text: 'Markets'),
                ],
              ),
            ),
            // The grid takes all the height the action bar does not need, and
            // scrolls on its own. Tabs are still built lazily.
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _RecordGrid<Party>(
                    color: AppColors.accent,
                    icon: AppIcons.farms,
                    emptyLabel: 'No farms in your zones yet',
                    loading: _loadingRecords,
                    error: _farmsError,
                    scope: _scope,
                    onRetry: _loadRecords,
                    items: _farms,
                    itemBuilder: (party) => _PartyGridTile(
                      party: party,
                      color: AppColors.accent,
                      statusColor: _statusColor,
                    ),
                    onTap: (party) => _open(
                      PartyDetailScreen(partyId: party.id, initialParty: party),
                    ),
                  ),
                  _RecordGrid<Party>(
                    color: AppColors.primary,
                    icon: AppIcons.store,
                    emptyLabel: 'No dealers in your zones yet',
                    loading: _loadingRecords,
                    error: _dealersError,
                    scope: _scope,
                    onRetry: _loadRecords,
                    items: _dealers,
                    itemBuilder: (party) => _PartyGridTile(
                      party: party,
                      color: AppColors.primary,
                      statusColor: _statusColor,
                    ),
                    onTap: (party) => _open(
                      PartyDetailScreen(partyId: party.id, initialParty: party),
                    ),
                  ),
                  _RecordGrid<Market>(
                    color: AppColors.secondary,
                    icon: AppIcons.store,
                    emptyLabel: 'No markets in your zones yet',
                    loading: _loadingRecords,
                    error: _marketsError,
                    scope: _scope,
                    onRetry: _loadRecords,
                    items: _markets,
                    itemBuilder: (market) => _MarketGridTile(
                      market: market,
                      color: AppColors.secondary,
                    ),
                    onTap: (market) =>
                        _open(MarketDetailScreen(market: market)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: _enabled
          ? _HubActionBar(
              controller: _tabController,
              labels: _tabActions,
              onCreate: _createFor,
              onViewAll: _viewAllFor,
              onFollowUps: () =>
                  _open(const FollowupFormScreen(showListMode: true)),
            )
          : null,
    );
  }
}

class _TabAction {
  const _TabAction(this.create, this.view, this.color);

  final String create;
  final String view;
  final Color color;
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

/// Create / View-all for the selected tab, plus the Follow-ups tile that used to
/// sit below the tabs.
///
/// Follow-ups moves in here rather than taking a row of grid height: it belongs
/// to no single tab and has to stay reachable from all three.
class _HubActionBar extends StatelessWidget {
  const _HubActionBar({
    required this.controller,
    required this.labels,
    required this.onCreate,
    required this.onViewAll,
    required this.onFollowUps,
  });

  final TabController controller;
  final List<_TabAction> labels;
  final void Function(int index) onCreate;
  final void Function(int index) onViewAll;
  final VoidCallback onFollowUps;

  @override
  Widget build(BuildContext context) {
    // AnimatedBuilder on the controller so the pills re-label on swipe without
    // rebuilding the whole screen body behind them.
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final index = controller.index.clamp(0, labels.length - 1);
        final label = labels[index];

        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.sm),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: AppPillButton(
                      icon: Icons.add_rounded,
                      label: label.create,
                      onTap: () => onCreate(index),
                      color: label.color,
                      dense: true,
                    ),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(
                    flex: 3,
                    child: AppPillButton(
                      icon: Icons.list_alt_outlined,
                      label: label.view,
                      onTap: () => onViewAll(index),
                      color: label.color,
                      filled: false,
                      dense: true,
                    ),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  // Fixed, so the two pills share the remaining width and the
                  // Follow-ups target never moves as the labels change.
                  AppIconTile(
                    icon: AppIcons.note,
                    color: AppColors.warning,
                    semanticLabel: 'Follow-ups',
                    onTap: onFollowUps,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A scrollable, full-height grid of records for one tab.
///
/// Owns the tab's loading, error and empty states and its pull-to-refresh,
/// because the grid is the scrollable here and `RefreshIndicator` has to wrap it.
class _RecordGrid<T> extends StatelessWidget {
  const _RecordGrid({
    required this.color,
    required this.icon,
    required this.emptyLabel,
    required this.loading,
    required this.error,
    required this.scope,
    required this.onRetry,
    required this.items,
    required this.itemBuilder,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String emptyLabel;
  final bool loading;
  final String? error;
  final ZoneScope? scope;

  /// Shared by the Retry button and the pull-to-refresh, and typed to return a
  /// Future so it satisfies `RefreshCallback` directly.
  final Future<void> Function() onRetry;
  final List<T> items;
  final Widget Function(T) itemBuilder;
  final ValueChanged<T> onTap;

  @override
  Widget build(BuildContext context) {
    // These states replace the grid rather than sitting inside it, so they fill
    // the tab instead of floating in a mostly empty scroll area.
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: AppEmptyState(
            icon: icon,
            title: 'Could not load',
            subtitle: error,
            tone: AppEmptyTone.error,
            // AppEmptyState takes a plain callback, so the async reload is
            // fire-and-forget here; it already guards its own setState.
            onRetry: () => onRetry(),
          ),
        ),
      );
    }
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: AppEmptyState(
            icon: icon,
            title: emptyLabel,
            subtitle: (scope != null && !scope!.isEmpty)
                ? 'These zones have none recorded yet.'
                : 'Tap Add to create the first one.',
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRetry,
      color: color,
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter, AppSpace.md, AppSpace.gutter, AppSpace.lg),
        // Max-cross-axis rather than a fixed count: two columns on a phone and
        // three or four on a tablet, matching how the rest of the app is
        // width-driven.
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 190,
          mainAxisSpacing: AppSpace.sm,
          crossAxisSpacing: AppSpace.sm,
          childAspectRatio: 0.78,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return InkWell(
            onTap: () => onTap(item),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: itemBuilder(item),
          );
        },
      ),
    );
  }
}

class _PartyGridTile extends StatelessWidget {
  const _PartyGridTile({
    required this.party,
    required this.color,
    required this.statusColor,
  });

  final Party party;
  final Color color;
  final Color Function(String?) statusColor;

  @override
  Widget build(BuildContext context) {
    final status = party.status;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border(left: BorderSide(color: color, width: 4)),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                party.isFarm ? AppIcons.farms : AppIcons.store,
                size: 20,
                color: color,
              ),
              const Spacer(),
              // AppIcons.* are getters, so this cannot be const.
              AppIcon(
                AppIcons.chevron,
                size: 16,
                color: AppColors.inkFaint,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Expanded(
            child: Text(
              party.displayName,
              style: AppType.bodySm.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            [
              if (party.marketName != null) party.marketName!,
              if (party.zoneName != null) party.zoneName!,
            ].join(' · '),
            style: AppType.micro.copyWith(color: AppColors.inkMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            party.phone ?? party.code ?? 'No phone',
            style: AppType.micro.copyWith(color: AppColors.inkFaint),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (status != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor(status).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                status,
                style: AppType.micro.copyWith(
                  fontWeight: FontWeight.w600,
                  color: statusColor(status),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MarketGridTile extends StatelessWidget {
  const _MarketGridTile({required this.market, required this.color});

  final Market market;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border(left: BorderSide(color: color, width: 4)),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.store, size: 20, color: color),
              const Spacer(),
              AppIcon(
                AppIcons.chevron,
                size: 16,
                color: AppColors.inkFaint,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Expanded(
            child: Text(
              market.name,
              style: AppType.bodySm.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            market.code ?? 'No code',
            style: AppType.micro.copyWith(color: AppColors.inkMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            market.locationLine.isEmpty ? 'No location' : market.locationLine,
            style: AppType.micro.copyWith(color: AppColors.inkFaint),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}