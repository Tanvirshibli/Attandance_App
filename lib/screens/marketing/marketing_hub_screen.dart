import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/theme.dart';
import '../../services/marketing_service.dart';
import '../../widgets/api_empty_state.dart';
import '../../widgets/gradient_screen_header.dart';
import '../../widgets/section_card.dart';
import 'followup_form_screen.dart';
import 'party_form_screen.dart';
import 'party_list_screen.dart';
import 'visit_list_screen.dart';

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
      floatingActionButton: !_enabled || _loading
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'new_farm',
                  onPressed: () => _open(
                    const PartyFormScreen(initialPartyType: 'farm'),
                  ),
                  backgroundColor: AppColors.accent,
                  icon: const Icon(Icons.agriculture, color: Colors.white),
                  label: Text(
                    'New Farm',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  heroTag: 'new_dealer',
                  onPressed: () => _open(
                    const PartyFormScreen(initialPartyType: 'dealer'),
                  ),
                  backgroundColor: AppColors.primary,
                  icon: const Icon(Icons.storefront_outlined, color: Colors.white),
                  label: Text(
                    'New Dealer',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(
            child: GradientScreenHeader(
              title: 'Farm & Dealer',
              subtitle: 'Field collection for dealers, farms & visits',
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.05,
                ),
                delegate: SliverChildListDelegate([
                  FadeInUp(
                    delay: const Duration(milliseconds: 40),
                    child: _HubTile(
                      icon: Icons.storefront_outlined,
                      label: 'Dealers',
                      color: AppColors.primary,
                      onTap: () => _open(
                        const PartyListScreen(initialPartyType: 'dealer'),
                      ),
                    ),
                  ),
                  FadeInUp(
                    delay: const Duration(milliseconds: 80),
                    child: _HubTile(
                      icon: Icons.agriculture_outlined,
                      label: 'Farms',
                      color: AppColors.accent,
                      onTap: () => _open(
                        const PartyListScreen(initialPartyType: 'farm'),
                      ),
                    ),
                  ),
                  FadeInUp(
                    delay: const Duration(milliseconds: 120),
                    child: _HubTile(
                      icon: Icons.route_outlined,
                      label: 'My visits',
                      color: AppColors.info,
                      onTap: () => _open(const VisitListScreen()),
                    ),
                  ),
                  FadeInUp(
                    delay: const Duration(milliseconds: 160),
                    child: _HubTile(
                      icon: Icons.event_note_outlined,
                      label: 'Follow-ups',
                      color: AppColors.warning,
                      onTap: () => _open(
                        const FollowupFormScreen(showListMode: true),
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

class _HubTile extends StatelessWidget {
  const _HubTile({
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
    return SectionCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
