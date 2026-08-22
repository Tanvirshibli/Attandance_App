import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/theme.dart';
import '../../models/marketing_models.dart';
import '../../services/marketing_service.dart';
import '../../widgets/api_empty_state.dart';
import '../../widgets/gradient_screen_header.dart';
import '../../widgets/section_card.dart';
import 'farm_survey_detail_screen.dart';
import 'farm_survey_form_screen.dart';
import 'followup_form_screen.dart';
import 'dealer_visit_form_screen.dart';

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
  bool _loadingRecords = true;
  String? _error;
  List<FarmSurvey> _surveys = const [];
  List<Visit> _visits = const [];

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
    await _loadRecords();
  }

  Future<void> _loadRecords() async {
    final party = _party;
    if (party == null) return;
    setState(() => _loadingRecords = true);
    if (party.isFarm) {
      final result = await _service.listFarmSurveys(partyId: party.id);
      if (!mounted) return;
      setState(() {
        _surveys = result.data ?? const [];
        _loadingRecords = false;
      });
      return;
    }
    final result = await _service.listVisits(partyId: party.id);
    if (!mounted) return;
    setState(() {
      _visits = result.data ?? const [];
      _loadingRecords = false;
    });
  }

  Future<void> _postVisit() async {
    final party = _party;
    if (party == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => party.isFarm
            ? FarmSurveyFormScreen(party: party)
            : DealerVisitFormScreen(party: party),
      ),
    );
    if (!mounted) return;
    _loadRecords();
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
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (party.ownerName != null)
                            _row('Owner', party.ownerName!),
                          if (party.phone != null) _row('Contact', party.phone!),
                          if (party.address != null)
                            _row('Address', party.address!),
                          if (party.parentPartyName != null)
                            _row('Dealer', party.parentPartyName!),
                          if (party.businessYears != null)
                            _row('Farming years', '${party.businessYears}'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _postVisit,
                            icon: const Icon(Icons.add, color: Colors.white),
                            label: Text(
                              'Post a visit',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: party.isFarm
                                  ? AppColors.accent
                                  : AppColors.primary,
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    FollowupFormScreen(party: party),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Icon(Icons.event_note_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      party.isFarm ? 'Visit reports' : 'Visits',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_loadingRecords)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (party.isFarm && _surveys.isEmpty)
                      const ApiEmptyState(
                        icon: Icons.assignment_outlined,
                        title: 'No visit reports yet',
                        subtitle: 'Post a visit to record this farm report.',
                      )
                    else if (!party.isFarm && _visits.isEmpty)
                      const ApiEmptyState(
                        icon: Icons.route_outlined,
                        title: 'No visits yet',
                        subtitle: 'Post a visit for this dealer.',
                      )
                    else if (party.isFarm)
                      ...List.generate(_surveys.length, (index) {
                        final survey = _surveys[index];
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
                                      builder: (_) => FarmSurveyDetailScreen(
                                        surveyId: survey.id,
                                        initial: survey,
                                      ),
                                    ),
                                  );
                                },
                                title: Text(
                                  survey.displayTitle,
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: Text(
                                  [
                                    if (survey.quantity != null)
                                      'Qty ${survey.quantity}',
                                    if (survey.ageDays != null)
                                      'Age ${survey.ageDays}d',
                                    if (survey.status != null) survey.status!,
                                  ].join(' · '),
                                  style: GoogleFonts.poppins(fontSize: 12),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                              ),
                            ),
                          ),
                        );
                      })
                    else
                      ...List.generate(_visits.length, (index) {
                        final visit = _visits[index];
                        return FadeInUp(
                          delay: Duration(milliseconds: 30 * index),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SectionCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    visit.displayName,
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    visit.status ?? '—',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
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
            width: 110,
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
