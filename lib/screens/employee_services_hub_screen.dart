import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';

import '../services/permission_service.dart';
import '../widgets/ui/ui.dart';
import 'attendance_report_screen.dart';
import 'geo_tracking_screen.dart';
import 'hr_benefits_hub_screen.dart';
import 'leave_hub_screen.dart';
import 'marketing/marketing_hub_screen.dart';
import 'payment_hub_screen.dart';
import 'sales_info_screen.dart';
import 'vehicle_list_screen.dart';

class EmployeeServicesHubScreen extends StatelessWidget {
  const EmployeeServicesHubScreen({super.key, this.showAsTabRoot = false});

  /// When true, hub is shown as a footer tab (no back button, title "Services").
  final bool showAsTabRoot;

  /// Every module the signed-in user may reach.
  ///
  /// [AppPermissions.moduleReadPermissions] decides visibility: a module absent
  /// from that map is unconditional, so Attendance, Leave, Payments and Sales
  /// info — the employee's own records rather than admin-managed modules —
  /// always show. A module keyed there appears only once
  /// [PermissionService] holds that user's grants.
  static List<_ServiceTileData> _visibleTiles() {
    final permissions = PermissionService.instance;
    final all = <_ServiceTileData>[
      _ServiceTileData(
        icon: AppIcons.attendance,
        label: 'Attendance report',
        color: AppColors.mAttendance,
        screen: const AttendanceReportScreen(),
      ),
      _ServiceTileData(
        icon: AppIcons.leave,
        label: 'Leave',
        color: AppColors.mLeave,
        screen: const LeaveHubScreen(),
      ),
      _ServiceTileData(
        icon: AppIcons.payments,
        label: 'Payments',
        color: AppColors.mPayments,
        screen: const PaymentHubScreen(),
      ),
      _ServiceTileData(
        icon: AppIcons.hr,
        label: 'HR benefits',
        color: AppColors.mHr,
        screen: const HrBenefitsHubScreen(),
        moduleKey: 'benefits',
      ),
      _ServiceTileData(
        icon: AppIcons.sales,
        label: 'Sales info',
        color: AppColors.mSales,
        screen: const SalesInfoScreen(),
      ),
      _ServiceTileData(
        icon: AppIcons.vehicles,
        label: 'Vehicles',
        color: AppColors.mVehicles,
        screen: const VehicleListScreen(),
        moduleKey: 'vehicles',
      ),
      _ServiceTileData(
        icon: AppIcons.farms,
        label: 'Farms & dealers',
        color: AppColors.mFarms,
        screen: const MarketingHubScreen(),
        moduleKey: 'marketing',
      ),
      _ServiceTileData(
        icon: AppIcons.geo,
        label: 'Geo tracking',
        color: AppColors.mGeo,
        screen: const GeoTrackingScreen(),
        moduleKey: 'tracking',
      ),
    ];

    return all.where((tile) => permissions.canViewModule(tile.moduleKey)).toList();
  }

  @override
  Widget build(BuildContext context) {
    // The permission list lands with the background profile fetch, after this
    // screen has already built once. Rebuilding on notify lets a tile appear
    // without waiting for the user to navigate away and back.
    return AnimatedBuilder(
      animation: PermissionService.instance,
      builder: (context, _) => _buildHub(PermissionService.instance),
    );
  }

  Widget _buildHub(PermissionService permissions) {
    final tiles = _visibleTiles();

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: AppHeader(
              title: showAsTabRoot ? 'Services' : 'Employee Services',
              subtitle: 'Everything your role unlocks',
              showBack: !showAsTabRoot,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter,
              AppSpace.md,
              AppSpace.gutter,
              AppSpace.lg,
            ),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: AppSpace.sm,
                crossAxisSpacing: AppSpace.sm,
                childAspectRatio: 0.92,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final tile = tiles[index];
                  return FadeInUp(
                    // Stagger follows the *filtered* index, so hiding a tile
                    // does not leave the remaining ones animating out of step.
                    delay: Duration(milliseconds: 60 * index),
                    child: _ServiceTile(tile: tile),
                  );
                },
                childCount: tiles.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceTileData {
  const _ServiceTileData({
    required this.icon,
    required this.label,
    required this.color,
    required this.screen,
    this.moduleKey,
  });

  final IconData icon;
  final String label;
  final Color color;

  /// Pre-built so the route stays an untyped
  /// `MaterialPageRoute(builder: (_) => screen)`, exactly as before.
  final Widget screen;

  /// Key into [AppPermissions.moduleReadPermissions]. Null means the module is
  /// ungated — the employee's own records, always available.
  final String? moduleKey;
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.tile});

  final _ServiceTileData tile;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => tile.screen),
          );
        },
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.sm + 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: AppColors.line),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIconTile(
                icon: tile.icon,
                color: tile.color,
                size: AppIconTileSize.large,
                semanticLabel: tile.label,
              ),
              const SizedBox(height: AppSpace.sm + 2),
              Flexible(
                child: Text(
                  // No hard-coded line breaks: the old labels carried a "\n"
                  // that split phrases mid-word ("Farms, Dealers\n& Markets").
                  // The grid now sizes itself to the text instead.
                  tile.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.h3.copyWith(
                    color: AppColors.ink,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
