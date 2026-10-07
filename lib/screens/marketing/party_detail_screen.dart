import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';

import '../../models/marketing_models.dart';
import '../../services/auth_service.dart';
import '../../services/marketing_service.dart';
import '../../widgets/marketing_photo_widgets.dart';
import '../../widgets/ui/ui.dart';
import 'dealer_visit_form_screen.dart';
import 'farm_survey_detail_screen.dart';
import 'farm_survey_form_screen.dart';
import 'followup_form_screen.dart';
import 'followup_row.dart';
import 'visit_detail_screen.dart';

class PartyDetailScreen extends StatefulWidget {
  const PartyDetailScreen({super.key, required this.partyId, this.initialParty});

  final int partyId;
  final Party? initialParty;

  @override
  State<PartyDetailScreen> createState() => _PartyDetailScreenState();
}

class _PartyDetailScreenState extends State<PartyDetailScreen>
    with SingleTickerProviderStateMixin {
  final MarketingService _service = MarketingService();
  final AuthService _authService = AuthService();
  late final TabController _tabs = TabController(length: 2, vsync: this);

  Party? _party;
  bool _loading = true;
  String? _error;
  List<FarmSurvey> _surveys = const [];
  List<Visit> _visits = const [];
  List<Followup> _followups = const [];
  bool _loadingVisits = true;
  bool _loadingFollowups = true;
  String? _visitsError;
  String? _followupsError;

  @override
  void initState() {
    super.initState();
    _party = widget.initialParty;
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
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
      // A party handed in by the caller can still feed its record lists
      // when this refresh failed.
      if (_party != null) {
        await _loadRecords();
      }
      return;
    }
    setState(() {
      _party = result.data;
      _loading = false;
    });
    await _loadRecords();
  }

  Future<void> _loadRecords() async {
    await Future.wait([_loadVisits(), _loadFollowups()]);
  }

  Future<void> _loadVisits() async {
    final party = _party;
    if (party == null) return;
    setState(() {
      _loadingVisits = true;
      _visitsError = null;
    });
    if (party.isFarm) {
      final result = await _service.listFarmSurveys(partyId: party.id);
      if (!mounted) return;
      setState(() {
        _surveys = result.data ?? const [];
        _visitsError =
            result.success ? null : (result.message ?? 'Could not load visit reports.');
        _loadingVisits = false;
      });
      return;
    }
    final result = await _service.listVisits(partyId: party.id);
    if (!mounted) return;
    setState(() {
      _visits = result.data ?? const [];
      _visitsError =
          result.success ? null : (result.message ?? 'Could not load visits.');
      _loadingVisits = false;
    });
  }

  Future<void> _loadFollowups() async {
    final party = _party;
    if (party == null) return;
    setState(() {
      _loadingFollowups = true;
      _followupsError = null;
    });
    final profile = await _authService.getCurrentUserProfile();
    final result = await _service.listFollowups(
      employeeId: profile?.canonicalEmployeeId,
      partyId: party.id,
    );
    if (!mounted) return;
    setState(() {
      _followups = result.data ?? const [];
      _followupsError =
          result.success ? null : (result.message ?? 'Could not load follow-ups.');
      _loadingFollowups = false;
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
    _tabs.animateTo(0);
    _loadVisits();
  }

  Future<void> _openFollowup() async {
    final party = _party;
    if (party == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FollowupFormScreen(party: party),
      ),
    );
    if (!mounted) return;
    _tabs.animateTo(1);
    _loadFollowups();
  }

  Future<void> _openFollowupItem(Followup item) async {
    final done = await showCompleteFollowupDialog(context, _service, item);
    if (!mounted || !done) return;
    _loadFollowups();
  }

  @override
  Widget build(BuildContext context) {
    final party = _party;
    if (party == null) return _loadingScaffold();
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            sliver: SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: AppHeader(
                    title: party.displayName,
                    subtitle: '${party.partyType} · ${party.status ?? '—'}',
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpace.gutter, AppSpace.md, AppSpace.gutter, 0),
                    child: _infoCard(party),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpace.gutter, 12, AppSpace.gutter, 8),
                    child: _pillRow(party),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabBarHeader(
                    TabBar(
                      controller: _tabs,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicatorWeight: 3,
                      dividerColor: AppColors.line,
                      labelStyle:
                          AppType.bodySm.copyWith(fontWeight: FontWeight.w700),
                      unselectedLabelStyle:
                          AppType.bodySm.copyWith(color: AppColors.inkMuted),
                      labelColor: AppColors.ink,
                      unselectedLabelColor: AppColors.inkMuted,
                      tabs: [
                        Tab(text: party.isFarm ? 'Visit reports' : 'Visits'),
                        const Tab(text: 'Follow-ups'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabs,
          children: [
            _visitsTab(party),
            _followupsTab(),
          ],
        ),
      ),
    );
  }

  Widget _loadingScaffold() {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            const SliverToBoxAdapter(
              child: AppHeader(title: 'Party', subtitle: 'Loading details…'),
            ),
            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: AppEmptyState(
                      icon: Icons.error_outline,
                      title: 'Could not load party',
                      subtitle: _error,
                      onRetry: _load,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(Party party) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (party.ownerName != null) _row('Owner', party.ownerName!),
          if (party.phone != null) _row('Contact', party.phone!),
          if (party.address != null) _row('Address', party.address!),
          if (party.parentPartyName != null)
            _row('Dealer', party.parentPartyName!),
          if (party.zoneName != null) _row('Zone', party.zoneName!),
          if (party.gelender != null && party.gelender!.isNotEmpty)
            _row('Gelender', party.gelender!),
          if (party.customerType != null && party.customerType!.isNotEmpty)
            _row('Customer type', party.customerType!),
          if (party.businessType != null && party.businessType!.isNotEmpty)
            _row('Business type', party.businessType!),
          if (party.businessYears != null)
            _row('Farming years', '${party.businessYears}'),
          // Farm-only. Both were collected by the standalone Add
          // Farm screen but nothing rendered them, so a farm
          // saved with a model-farm classification looked
          // identical to a regular one.
          if (party.isFarm && party.visitType != null)
            _row('Visit type', _label(party.visitType!)),
          if (party.isFarm && party.farmType != null)
            _row('Farm type', _label(party.farmType!)),
          if (party.isFarm && party.capacity != null)
            _row('Capacity', '${party.capacity}'),
          if (party.isFarm && party.capacityLimit != null)
            _row('Capacity limit', '${party.capacityLimit}'),
          // The photos uploaded when the record was posted.
          if (marketingPhotoUrls(party.attachments).isNotEmpty)
            MarketingPhotoGrid(attachments: party.attachments),
        ],
      ),
    );
  }

  Widget _pillRow(Party party) {
    return Row(
      children: [
        Expanded(
          child: AppPillButton(
            icon: Icons.add_rounded,
            label: 'Post a visit',
            onTap: _postVisit,
            color: party.isFarm ? AppColors.accent : AppColors.primary,
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        AppPillButton(
          icon: Icons.event_note_outlined,
          label: 'New follow-up',
          onTap: _openFollowup,
          color: AppColors.warning,
          filled: false,
        ),
      ],
    );
  }

  Widget _visitsTab(Party party) {
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: Builder(
        builder: (context) => CustomScrollView(
          key: const PageStorageKey<String>('party-visits'),
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            if (_loadingVisits)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_visitsError != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: AppEmptyState(
                      icon: Icons.error_outline,
                      title: 'Could not load',
                      subtitle: _visitsError,
                      onRetry: _loadVisits,
                    ),
                  ),
                ),
              )
            else if (party.isFarm && _surveys.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: AppEmptyState(
                      icon: AppIcons.note,
                      title: 'No visit reports yet',
                      subtitle: 'Post a visit to record this farm report.',
                    ),
                  ),
                ),
              )
            else if (!party.isFarm && _visits.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: AppEmptyState(
                      icon: AppIcons.route,
                      title: 'No visits yet',
                      subtitle: 'Post a visit for this dealer.',
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpace.gutter, AppSpace.md, AppSpace.gutter, AppSpace.xl),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        party.isFarm ? _surveyRow(index) : _visitRow(index),
                    childCount: party.isFarm ? _surveys.length : _visits.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _followupsTab() {
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: Builder(
        builder: (context) => CustomScrollView(
          key: const PageStorageKey<String>('party-followups'),
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            if (_loadingFollowups)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_followupsError != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: AppEmptyState(
                      icon: Icons.error_outline,
                      title: 'Could not load',
                      subtitle: _followupsError,
                      onRetry: _loadFollowups,
                    ),
                  ),
                ),
              )
            else if (_followups.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: AppEmptyState(
                      icon: Icons.event_note_outlined,
                      title: 'No follow-ups yet',
                      subtitle: 'Create a follow-up from this page.',
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpace.gutter, AppSpace.md, AppSpace.gutter, AppSpace.xl),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = _followups[index];
                      return FadeInUp(
                        delay: Duration(milliseconds: 30 * index),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: FollowupRow(
                            item: item,
                            showPartyName: false,
                            onTap: FollowupRow.canComplete(item.status)
                                ? () => _openFollowupItem(item)
                                : null,
                          ),
                        ),
                      );
                    },
                    childCount: _followups.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _surveyRow(int index) {
    final survey = _surveys[index];
    return FadeInUp(
      delay: Duration(milliseconds: 30 * index),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AppCard(
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
            leading: marketingPhotoUrls(survey.attachments).isEmpty
                ? null
                : MarketingThumb(attachments: survey.attachments, size: 48),
            title: Text(
              survey.displayTitle,
              style: AppType.body.copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              [
                if (survey.quantity != null) 'Qty ${survey.quantity}',
                if (survey.ageDays != null) 'Age ${survey.ageDays}d',
                if (survey.status != null) survey.status!,
              ].join(' · '),
              style: AppType.meta,
            ),
            trailing: const Icon(Icons.chevron_right),
          ),
        ),
      ),
    );
  }

  Widget _visitRow(int index) {
    final visit = _visits[index];
    return FadeInUp(
      delay: Duration(milliseconds: 30 * index),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AppCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => VisitDetailScreen(
                    visitId: visit.id,
                    initial: visit,
                  ),
                ),
              );
              if (mounted) _loadVisits();
            },
            leading: marketingPhotoUrls(visit.attachments).isEmpty
                ? null
                : MarketingThumb(attachments: visit.attachments, size: 48),
            title: Text(
              visit.displayName,
              style: AppType.body.copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              visit.status ?? '—',
              style: AppType.meta.copyWith(color: AppColors.inkMuted),
            ),
            trailing: const Icon(Icons.chevron_right),
          ),
        ),
      ),
    );
  }

  /// Turns a stored enum-ish value into the words the officer picked.
  ///
  /// The API stores `regular_farm` / `broiler`; a detail screen showing raw
  /// slugs reads like a database dump rather than a record. An unmapped value
  /// is passed through rather than hidden — a new server-side option should show
  /// up as itself, not vanish.
  static String _label(String value) {
    const labels = {
      'regular_farm': 'Regular farm',
      'model_farm': 'Model farm',
      'other_farm': 'Other farm',
      'broiler': 'Broiler',
      'layer': 'Layer',
      'color': 'Color',
      'all': 'All',
    };
    return labels[value.toLowerCase()] ?? value;
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
              style: AppType.meta.copyWith(color: AppColors.inkMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppType.bodySm.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// A pinned, fixed-height tab bar for the detail page's header.
class _TabBarHeader extends SliverPersistentHeaderDelegate {
  const _TabBarHeader(this.tabBar);

  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: AppColors.canvas, child: tabBar);
  }

  @override
  bool shouldRebuild(covariant _TabBarHeader oldDelegate) =>
      oldDelegate.tabBar != tabBar;
}
