import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import '../models/vehicle_models.dart';
import '../services/vehicle_service.dart';
import '../widgets/api_empty_state.dart';
import '../widgets/filter_chip_row.dart';
import '../widgets/gradient_screen_header.dart';
import '../widgets/section_card.dart';
import 'vehicle_detail_screen.dart';

class VehicleTripListScreen extends StatefulWidget {
  const VehicleTripListScreen({super.key, required this.vehicle});

  final VehicleSummary vehicle;

  @override
  State<VehicleTripListScreen> createState() => _VehicleTripListScreenState();
}

class _VehicleTripListScreenState extends State<VehicleTripListScreen> {
  static const _chipOptions = [
    'All',
    'In transit',
    'Delivered',
    'Draft',
    'Cancelled',
    'Archived',
  ];

  final VehicleService _vehicleService = VehicleService();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _loadingMore = false;
  bool _featureDisabled = false;
  String? _error;
  String _chip = 'All';
  int _currentPage = 0;
  int _lastPage = 1;
  final List<Trip> _trips = [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  bool get _hasMore =>
      !_featureDisabled && _currentPage > 0 && _currentPage < _lastPage;

  List<Trip> get _visibleTrips {
    if (_chip == 'All') return List<Trip>.from(_trips);
    final key = _chipStatusKey(_chip);
    return _trips.where((t) {
      final status = t.status.toLowerCase();
      if (key == 'cancelled') {
        return status == 'cancelled' || status == 'canceled';
      }
      return status == key;
    }).toList();
  }

  static String _chipStatusKey(String chip) {
    switch (chip) {
      case 'In transit':
        return 'intransit';
      case 'Delivered':
        return 'delivered';
      case 'Draft':
        return 'draft';
      case 'Cancelled':
        return 'cancelled';
      case 'Archived':
        return 'archived';
      default:
        return '';
    }
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _isLoading) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      _load(reset: false);
    }
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _loadingMore = false;
        _error = null;
        _featureDisabled = false;
        _trips.clear();
        _currentPage = 0;
        _lastPage = 1;
      });
    } else {
      if (_loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    }

    final nextPage = reset ? 1 : _currentPage + 1;
    final result = await _vehicleService.getTrips(
      page: nextPage,
      vehicleId: widget.vehicle.id,
    );
    if (!mounted) return;

    if (!result.success || result.data == null) {
      setState(() {
        _featureDisabled = result.message == 'feature_disabled';
        _error = result.message == 'feature_disabled'
            ? null
            : (result.message ?? 'Could not load trips.');
        _isLoading = false;
        _loadingMore = false;
      });
      return;
    }

    final page = result.data!;
    final seen = _trips.map((t) => t.id).toSet();
    setState(() {
      for (final trip in page.trips) {
        if (seen.add(trip.id)) {
          _trips.add(trip);
        }
      }
      _currentPage = page.currentPage;
      _lastPage = page.lastPage;
      _error = null;
      _featureDisabled = false;
      _isLoading = false;
      _loadingMore = false;
    });
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'intransit':
        return AppColors.info;
      case 'delivered':
        return AppColors.success;
      case 'cancelled':
      case 'canceled':
        return AppColors.error;
      case 'archived':
        return AppColors.textHint;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleTrips;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: GradientScreenHeader(
                title: 'Trips',
                subtitle: widget.vehicle.displayPlate,
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: FilterChipRow(
                  options: _chipOptions,
                  selected: _chip,
                  onSelected: (v) => setState(() => _chip = v),
                ),
              ),
            ),
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_featureDisabled)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ApiEmptyState(
                      icon: Icons.directions_car_outlined,
                      title: 'Vehicles module disabled',
                      subtitle:
                          'Vehicles are turned off in mobile app settings. Ask an admin to enable the Vehicles module.',
                      onRetry: () => _load(reset: true),
                    ),
                  ),
                ),
              )
            else if (_error != null && _trips.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ApiEmptyState(
                      icon: Icons.error_outline,
                      title: 'Could not load trips',
                      subtitle: _error!,
                      onRetry: () => _load(reset: true),
                    ),
                  ),
                ),
              )
            else if (visible.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ApiEmptyState(
                      icon: Icons.route_outlined,
                      title: _trips.isEmpty
                          ? 'No trips for this vehicle'
                          : 'No trips in this filter',
                      subtitle: _hasMore
                          ? 'Load more pages to find trips for this vehicle.'
                          : 'Trips for this vehicle will appear here.',
                      onRetry: _hasMore
                          ? () => _load(reset: false)
                          : () => _load(reset: true),
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
                      if (index == visible.length) {
                        return _buildLoadMore();
                      }
                      final trip = visible[index];
                      return FadeInUp(
                        delay: Duration(milliseconds: 30 * (index % 12)),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _TripListTile(
                            trip: trip,
                            statusColor: _statusColor(trip.status),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    VehicleDetailScreen(trip: trip),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: visible.length + 1,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadMore() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_hasMore) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'All loaded pages shown',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: AppColors.textHint,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Center(
        child: TextButton(
          onPressed: () => _load(reset: false),
          child: Text(
            'Load more',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _TripListTile extends StatelessWidget {
  const _TripListTile({
    required this.trip,
    required this.statusColor,
    required this.onTap,
  });

  final Trip trip;
  final Color statusColor;
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
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.local_shipping_outlined, color: statusColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            trip.tripCode.isEmpty
                                ? 'Trip #${trip.id}'
                                : trip.tripCode,
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            trip.statusLabel,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (trip.tripTitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        trip.tripTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      [
                        trip.plate,
                        formatTripDate(trip.startDateTime),
                      ].join(' · '),
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      trip.routeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
