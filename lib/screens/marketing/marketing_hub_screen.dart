import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/theme.dart';
import '../../models/marketing_models.dart';
import '../../services/auth_service.dart';
import '../../services/marketing_service.dart';
import '../../widgets/api_empty_state.dart';
import '../../widgets/gradient_screen_header.dart';
import '../../widgets/section_card.dart';
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
  final AuthService _authService = AuthService();

  bool _loadingFeature = true;
  bool _enabled = true;
  bool _loadingPreviews = false;

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

    final profile = await _authService.getCurrentUserProfile();
    final employeeId = profile?.canonicalEmployeeId;

    final farmsFuture = _service.listParties(
      employeeId: employeeId,
      partyType: 'farm',
      limit: _previewLimit,
    );
    final dealersFuture = _service.listParties(
      employeeId: employeeId,
      partyType: 'dealer',
      limit: _previewLimit,
    );
    final marketsFuture = _service.listMarkets(limit: _previewLimit);

    final farmsResult = await farmsFuture;
    final dealersResult = await dealersFuture;
    final marketsResult = await marketsFuture;

    setState(() {
      _loadingPreviews = false;
      if (farmsResult.success) {
        _farms = farmsResult.data ?? const [];
      } else {
        _farms = const [];
        _farmsError = farmsResult.message ?? 'Could not load farms.';
      }
      if (dealersResult.success) {
        _dealers = dealersResult.data ?? const [];
      } else {
        _dealers = const [];
        _dealersError = dealersResult.message ?? 'Could not load dealers.';
      }
      if (marketsResult.success) {
        _markets = marketsResult.data ?? const [];
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
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _enabled ? _loadPreviews : _init,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            const SliverToBoxAdapter(
              child: GradientScreenHeader(
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
                    child: ApiEmptyState(
                      icon: Icons.agriculture_outlined,
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    FadeInUp(
                      delay: const Duration(milliseconds: 40),
                      child: _HubGroupCard(
                        icon: Icons.agriculture_outlined,
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
                        icon: Icons.storefront_outlined,
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
                        icon: Icons.store_mall_directory_outlined,
                        label: 'Markets',
                        color: AppColors.info,
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
                      child: SectionCard(
                        padding: EdgeInsets.zero,
                        child: InkWell(
                          onTap: () => _open(
                            const FollowupFormScreen(showListMode: true),
                          ),
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: AppColors.warning.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.event_note_outlined,
                                    color: AppColors.warning,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Follow-ups',
                                        style: GoogleFonts.poppins(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        'Tasks and reminders',
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  color: AppColors.textHint,
                                ),
                              ],
                            ),
                          ),
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
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border(
          left: BorderSide(color: color, width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
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
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
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
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.error,
                      ),
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
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
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
                  Icon(
                    parties[i].isFarm
                        ? Icons.agriculture_outlined
                        : Icons.storefront_outlined,
                    size: 18,
                    color: color,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          parties[i].displayName,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
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
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
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
                        style: GoogleFonts.poppins(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: statusColor(parties[i].status),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.textHint,
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
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
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
                  const Icon(
                    Icons.store_mall_directory_outlined,
                    size: 18,
                    color: AppColors.info,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          markets[i].displayName,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (markets[i].locationLine.isNotEmpty)
                          Text(
                            markets[i].locationLine,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.textHint,
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
