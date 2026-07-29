import 'package:animate_do/animate_do.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/theme.dart';
import '../../models/marketing_models.dart';
import '../../services/marketing_service.dart';
import '../../widgets/api_empty_state.dart';
import '../../widgets/gradient_screen_header.dart';
import '../../widgets/section_card.dart';
import 'farm_survey_form_screen.dart';
import 'followup_form_screen.dart';
import 'visit_form_screen.dart';

class PartyDetailScreen extends StatefulWidget {
  const PartyDetailScreen({super.key, required this.partyId, this.initialParty});

  final int partyId;
  final Party? initialParty;

  @override
  State<PartyDetailScreen> createState() => _PartyDetailScreenState();
}

class _PartyDetailScreenState extends State<PartyDetailScreen> {
  final MarketingService _service = MarketingService();
  Party? _party;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _party = widget.initialParty;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _service.getParty(widget.partyId);
    if (!mounted) return;
    if (!result.success || result.data == null) {
      setState(() {
        _error = result.message ?? 'Could not load party.';
        _loading = false;
      });
      return;
    }
    setState(() {
      _party = result.data;
      _loading = false;
    });
  }

  Widget _actionChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ActionChip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(
        label,
        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      onPressed: onTap,
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide(color: color.withValues(alpha: 0.25)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final party = _party;
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
                title: party?.displayName ?? 'Party',
                subtitle: party != null
                    ? '${party.partyType} · ${party.status ?? '—'}'
                    : 'Loading details…',
              ),
            ),
            if (_loading && party == null)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && party == null)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ApiEmptyState(
                      icon: Icons.error_outline,
                      title: 'Could not load party',
                      subtitle: _error,
                      onRetry: _load,
                    ),
                  ),
                ),
              )
            else if (party != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    FadeInUp(
                      child: SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _row('Name', party.name),
                            if (party.tradeName != null)
                              _row('Trade name', party.tradeName!),
                            if (party.contactPerson != null)
                              _row('Contact', party.contactPerson!),
                            if (party.phone != null) _row('Phone', party.phone!),
                            if (party.address != null)
                              _row('Address', party.address!),
                            if (party.marketName != null)
                              _row('Market', party.marketName!),
                            if (party.lat != null && party.lng != null)
                              _row(
                                'GPS',
                                '${party.lat!.toStringAsFixed(5)}, ${party.lng!.toStringAsFixed(5)}',
                              ),
                            if (party.notes != null) _row('Notes', party.notes!),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FadeInUp(
                      delay: const Duration(milliseconds: 60),
                      child: SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Actions',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _actionChip(
                                  icon: Icons.route_outlined,
                                  label: 'New Visit',
                                  color: AppColors.info,
                                  onTap: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            VisitFormScreen(party: party),
                                      ),
                                    );
                                    _load();
                                  },
                                ),
                                if (party.isFarm)
                                  _actionChip(
                                    icon: Icons.assessment_outlined,
                                    label: 'Farm Survey',
                                    color: AppColors.accent,
                                    onTap: () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => FarmSurveyFormScreen(
                                            party: party,
                                          ),
                                        ),
                                      );
                                      _load();
                                    },
                                  ),
                                _actionChip(
                                  icon: Icons.event_note_outlined,
                                  label: 'Follow-up',
                                  color: AppColors.warning,
                                  onTap: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => FollowupFormScreen(
                                          party: party,
                                        ),
                                      ),
                                    );
                                    _load();
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (party.products.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      FadeInUp(
                        delay: const Duration(milliseconds: 100),
                        child: SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Products',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...party.products.map(
                                (p) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          p.productName,
                                          style: GoogleFonts.poppins(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        [
                                          if (p.demandQty != null)
                                            'D:${p.demandQty}',
                                          if (p.stockQty != null)
                                            'S:${p.stockQty}',
                                          if (p.competitorBrand != null)
                                            p.competitorBrand!,
                                        ].join(' · '),
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (party.attachments.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      FadeInUp(
                        delay: const Duration(milliseconds: 140),
                        child: SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Photos',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 88,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: party.attachments.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: 8),
                                  itemBuilder: (context, i) {
                                    final att = party.attachments[i];
                                    final url = att.displayUrl;
                                    return ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: url == null
                                          ? Container(
                                              width: 88,
                                              color: AppColors.background,
                                              child: const Icon(
                                                Icons.image_outlined,
                                              ),
                                            )
                                          : CachedNetworkImage(
                                              imageUrl: url,
                                              width: 88,
                                              height: 88,
                                              fit: BoxFit.cover,
                                              errorWidget: (_, _, _) =>
                                                  Container(
                                                width: 88,
                                                color: AppColors.background,
                                                child: const Icon(
                                                  Icons.broken_image_outlined,
                                                ),
                                              ),
                                            ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
