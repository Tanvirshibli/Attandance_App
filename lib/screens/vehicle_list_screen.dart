import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import '../models/vehicle_models.dart';
import '../services/vehicle_service.dart';
import '../widgets/api_empty_state.dart';
import '../widgets/gradient_screen_header.dart';
import '../widgets/section_card.dart';
import 'vehicle_hub_screen.dart';

class VehicleListScreen extends StatefulWidget {
  const VehicleListScreen({super.key});

  @override
  State<VehicleListScreen> createState() => _VehicleListScreenState();
}

class _VehicleListScreenState extends State<VehicleListScreen> {
  final VehicleService _vehicleService = VehicleService();

  bool _isLoading = true;
  bool _featureDisabled = false;
  String? _error;
  List<VehicleSummary> _vehicles = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _featureDisabled = false;
    });

    final result = await _vehicleService.getActiveVehicles();
    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _vehicles = const [];
        _featureDisabled = result.message == 'feature_disabled';
        _error = result.message == 'feature_disabled'
            ? null
            : (result.message ?? 'Could not load vehicles.');
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _vehicles = result.data ?? const [];
      _error = null;
      _featureDisabled = false;
      _isLoading = false;
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
                title: 'Vehicles',
                subtitle: 'Active fleet',
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
                      onRetry: _load,
                    ),
                  ),
                ),
              )
            else if (_error != null)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ApiEmptyState(
                      icon: Icons.error_outline,
                      title: 'Could not load vehicles',
                      subtitle: _error!,
                      onRetry: _load,
                    ),
                  ),
                ),
              )
            else if (_vehicles.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: ApiEmptyState(
                      icon: Icons.directions_car_outlined,
                      title: 'No active vehicles',
                      subtitle:
                          'Active vehicles will appear here when available.',
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
                      final vehicle = _vehicles[index];
                      return FadeInUp(
                        delay: Duration(milliseconds: 40 * index),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SectionCard(
                            padding: EdgeInsets.zero,
                            child: InkWell(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      VehicleHubScreen(vehicle: vehicle),
                                ),
                              ),
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        color: AppColors.info
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: const Icon(
                                        Icons.directions_car_outlined,
                                        color: AppColors.info,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            vehicle.displayPlate,
                                            style: GoogleFonts.poppins(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Purchased ${vehicle.formattedPurchaseDate}',
                                            style: GoogleFonts.poppins(
                                              fontSize: 12,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                          if (vehicle.tVehicleNo
                                                  .trim()
                                                  .isNotEmpty &&
                                              vehicle.tVehicleNo.trim() !=
                                                  vehicle.displayPlate)
                                            Text(
                                              vehicle.tVehicleNo,
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
                          ),
                        ),
                      );
                    },
                    childCount: _vehicles.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
