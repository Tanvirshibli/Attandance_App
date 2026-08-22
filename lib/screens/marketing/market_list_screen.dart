import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/theme.dart';
import '../../models/marketing_models.dart';
import '../../services/marketing_service.dart';
import '../../widgets/api_empty_state.dart';
import '../../widgets/gradient_screen_header.dart';
import '../../widgets/section_card.dart';
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
    setState(() {
      _markets = result.data ?? const [];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            const SliverToBoxAdapter(
              child: GradientScreenHeader(
                title: 'Markets',
                subtitle: 'Bazaars & coverage areas',
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
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
                    suffixIcon: IconButton(
                      onPressed: _load,
                      icon: const Icon(Icons.arrow_forward),
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
            else if (_markets.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: ApiEmptyState(
                      icon: Icons.store_mall_directory_outlined,
                      title: 'No markets yet',
                      subtitle: 'Create a market to assign dealers and farms.',
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final m = _markets[index];
                      final loc = m.locationLine;
                      return FadeInUp(
                        delay: Duration(milliseconds: 30 * index),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: SectionCard(
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
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                                    if (loc.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        loc,
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                    if (m.status != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        m.status!,
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
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
