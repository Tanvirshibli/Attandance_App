import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/theme.dart';
import '../../services/marketing_service.dart';
import '../../widgets/api_empty_state.dart';
import '../../widgets/gradient_screen_header.dart';
import '../../widgets/section_card.dart';
import 'followup_form_screen.dart';
import 'market_form_screen.dart';
import 'market_list_screen.dart';
import 'party_form_screen.dart';
import 'party_list_screen.dart';

class MarketingHubScreen extends StatefulWidget {
  const MarketingHubScreen({super.key});

  @override
  State<MarketingHubScreen> createState() => _MarketingHubScreenState();
}

class _MarketingHubScreenState extends State<MarketingHubScreen> {
  final MarketingService _service = MarketingService();
  bool _loading = true;
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    _checkFeature();
  }

  Future<void> _checkFeature() async {
    final enabled = await _service.isMarketingEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _loading = false;
    });
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(
            child: GradientScreenHeader(
              title: 'Farm & Dealer',
              subtitle: 'Create or view markets, dealers and farms',
            ),
          ),
          if (_loading)
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
                    title: 'Farm & Dealer disabled',
                    subtitle:
                        'Ask an admin to enable marketing.enabled in mobile app settings.',
                    onRetry: _checkFeature,
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
                      icon: Icons.store_mall_directory_outlined,
                      label: 'Markets',
                      color: AppColors.info,
                      createLabel: 'Create market',
                      viewLabel: 'View all markets',
                      onCreate: () => _open(const MarketFormScreen()),
                      onView: () => _open(const MarketListScreen()),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FadeInUp(
                    delay: const Duration(milliseconds: 80),
                    child: _HubGroupCard(
                      icon: Icons.storefront_outlined,
                      label: 'Dealers',
                      color: AppColors.primary,
                      createLabel: 'Create dealer',
                      viewLabel: 'View all dealers',
                      onCreate: () => _open(
                        const PartyFormScreen(initialPartyType: 'dealer'),
                      ),
                      onView: () => _open(
                        const PartyListScreen(initialPartyType: 'dealer'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FadeInUp(
                    delay: const Duration(milliseconds: 120),
                    child: _HubGroupCard(
                      icon: Icons.agriculture_outlined,
                      label: 'Farms',
                      color: AppColors.accent,
                      createLabel: 'Create farm',
                      viewLabel: 'View all farms',
                      onCreate: () => _open(
                        const PartyFormScreen(initialPartyType: 'farm'),
                      ),
                      onView: () => _open(
                        const PartyListScreen(initialPartyType: 'farm'),
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
    );
  }
}

class _HubGroupCard extends StatelessWidget {
  const _HubGroupCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.createLabel,
    required this.viewLabel,
    required this.onCreate,
    required this.onView,
  });

  final IconData icon;
  final String label;
  final Color color;
  final String createLabel;
  final String viewLabel;
  final VoidCallback onCreate;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SubCard(
                  icon: Icons.add_rounded,
                  label: createLabel,
                  color: color,
                  onTap: onCreate,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SubCard(
                  icon: Icons.list_alt_outlined,
                  label: viewLabel,
                  color: color,
                  onTap: onView,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SubCard extends StatelessWidget {
  const _SubCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
