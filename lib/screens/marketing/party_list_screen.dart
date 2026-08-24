import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/theme.dart';
import '../../models/marketing_models.dart';
import '../../services/marketing_service.dart';
import '../../widgets/api_empty_state.dart';
import '../../widgets/filter_chip_row.dart';
import '../../widgets/gradient_screen_header.dart';
import '../../widgets/section_card.dart';
import 'party_detail_screen.dart';

class PartyListScreen extends StatefulWidget {
  const PartyListScreen({
    super.key,
    this.initialPartyType,
    this.marketId,
  });

  final String? initialPartyType;
  final int? marketId;

  @override
  State<PartyListScreen> createState() => _PartyListScreenState();
}

class _PartyListScreenState extends State<PartyListScreen> {
  final MarketingService _service = MarketingService();
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Party> _parties = const [];
  late String _typeFilter;
  String _statusFilter = 'All';

  static const _typeOptions = ['All', 'dealer', 'farm', 'farmer', 'outlet', 'prospect'];
  static const _statusOptions = ['All', 'active', 'inactive', 'prospect'];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPartyType?.toLowerCase();
    _typeFilter = (initial != null && _typeOptions.contains(initial))
        ? initial
        : 'All';
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // Master lists are company-wide (omit employee_id).
    final result = await _service.listParties(
      partyType: _typeFilter == 'All' ? null : _typeFilter,
      q: _searchController.text,
      status: _statusFilter,
      marketId: widget.marketId,
    );

    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _parties = const [];
        _error = result.message == 'feature_disabled'
            ? 'Farm & Dealer module is disabled.'
            : (result.message ?? 'Could not load parties.');
        _loading = false;
      });
      return;
    }

    setState(() {
      _parties = result.data ?? const [];
      _loading = false;
    });
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
    final title = widget.initialPartyType == 'dealer'
        ? 'Dealers'
        : widget.initialPartyType == 'farm'
            ? 'Farms'
            : 'Parties';

    final lockType = widget.initialPartyType != null;
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
                title: title,
                subtitle: 'Search & filter field parties',
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _searchController,
                      onSubmitted: (_) => _load(),
                      decoration: InputDecoration(
                        hintText: 'Search name, phone, code…',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.arrow_forward_rounded),
                          onPressed: _load,
                        ),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    if (!lockType) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Type',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      FilterChipRow(
                        options: _typeOptions,
                        selected: _typeFilter,
                        onSelected: (v) {
                          setState(() => _typeFilter = v);
                          _load();
                        },
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'Status',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    FilterChipRow(
                      options: _statusOptions,
                      selected: _statusFilter,
                      onSelected: (v) {
                        setState(() => _statusFilter = v);
                        _load();
                      },
                    ),
                  ],
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
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ApiEmptyState(
                      icon: Icons.storefront_outlined,
                      title: 'No parties found',
                      subtitle: 'Create a dealer or farm to get started.',
                      onRetry: _load,
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
                      final party = _parties[index];
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
                                        PartyDetailScreen(partyId: party.id),
                                  ),
                                );
                                _load();
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: (party.isFarm
                                                ? AppColors.accent
                                                : AppColors.primary)
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(
                                        party.isFarm
                                            ? Icons.agriculture_outlined
                                            : Icons.storefront_outlined,
                                        color: party.isFarm
                                            ? AppColors.accent
                                            : AppColors.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            party.displayName,
                                            style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            [
                                              party.partyType,
                                              if (party.phone != null)
                                                party.phone!,
                                              if (party.marketName != null)
                                                party.marketName!,
                                            ].join(' · '),
                                            style: GoogleFonts.poppins(
                                              fontSize: 11,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _statusColor(party.status)
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        party.status ?? '—',
                                        style: GoogleFonts.poppins(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: _statusColor(party.status),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
