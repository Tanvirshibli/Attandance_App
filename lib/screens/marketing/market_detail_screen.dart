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
import 'party_detail_screen.dart';

class MarketDetailScreen extends StatefulWidget {
  const MarketDetailScreen({super.key, required this.market});

  final Market market;

  @override
  State<MarketDetailScreen> createState() => _MarketDetailScreenState();
}

class _MarketDetailScreenState extends State<MarketDetailScreen> {
  final MarketingService _service = MarketingService();
  final AuthService _authService = AuthService();
  bool _loading = true;
  String? _error;
  List<Party> _parties = const [];

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
    final result = await _service.listParties(
      employeeId: profile?.canonicalEmployeeId,
      marketId: widget.market.id,
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

  @override
  Widget build(BuildContext context) {
    final market = widget.market;
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
                subtitle: loc.isNotEmpty ? loc : 'Market records',
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              sliver: SliverToBoxAdapter(
                child: SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (market.address != null)
                        Text(
                          market.address!,
                          style: GoogleFonts.poppins(fontSize: 13),
                        ),
                      if (market.status != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          market.status!,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: AppColors.info,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
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
