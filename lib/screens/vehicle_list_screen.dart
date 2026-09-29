import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';

import '../models/vehicle_models.dart';
import '../services/vehicle_service.dart';
import '../widgets/ui/ui.dart';
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
              child: AppHeader(
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
                    child: AppEmptyState(
                      icon: AppIcons.vehicles,
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
                    child: AppEmptyState(
                      icon: AppIcons.error,
                      title: 'Could not load vehicles',
                      subtitle: _error!,
                      onRetry: _load,
                    ),
                  ),
                ),
              )
            else if (_vehicles.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: AppEmptyState(
                      icon: AppIcons.vehicles,
                      title: 'No active vehicles',
                      subtitle:
                          'Active vehicles will appear here when available.',
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.md, AppSpace.gutter, AppSpace.xl),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final vehicle = _vehicles[index];
                      return FadeInUp(
                        delay: Duration(milliseconds: 40 * index),
                        child: Padding(
                          padding:
                              const EdgeInsets.only(bottom: AppSpace.sm),
                          // Fire-and-forget push; no result is used and the
                          // list is not reloaded on return. Unchanged.
                          child: AppCard(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    VehicleHubScreen(vehicle: vehicle),
                              ),
                            ),
                            padding: const EdgeInsets.all(AppSpace.sm + 2),
                            child: Row(
                              children: [
                                AppIconTile(
                                  icon: AppIcons.vehicles,
                                  color: AppColors.mVehicles,
                                  semanticLabel: vehicle.displayPlate,
                                ),
                                const SizedBox(width: AppSpace.sm + 2),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        vehicle.displayPlate,
                                        style: AppType.h3
                                            .copyWith(color: AppColors.ink),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Purchased ${vehicle.formattedPurchaseDate}',
                                        style: AppType.meta.copyWith(
                                          color: AppColors.inkMuted,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (vehicle.tVehicleNo
                                              .trim()
                                              .isNotEmpty &&
                                          vehicle.tVehicleNo.trim() !=
                                              vehicle.displayPlate)
                                        Text(
                                          vehicle.tVehicleNo,
                                          style: AppType.micro.copyWith(
                                            color: AppColors.inkFaint,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                AppIcon(
                                  AppIcons.chevron,
                                  size: 18,
                                  color: AppColors.inkFaint,
                                ),
                              ],
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
