import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import 'attendance_report_screen.dart';
import 'geo_tracking_screen.dart';
import 'leave_hub_screen.dart';
import 'payment_hub_screen.dart';
import 'sales_info_screen.dart';
import '../widgets/gradient_screen_header.dart';

class EmployeeServicesHubScreen extends StatelessWidget {
  const EmployeeServicesHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _ServiceTileData(
        icon: Icons.fact_check_outlined,
        label: 'Attendance\nReport',
        color: AppColors.primary,
        screen: const AttendanceReportScreen(),
      ),
      _ServiceTileData(
        icon: Icons.beach_access_outlined,
        label: 'Leave',
        color: AppColors.info,
        screen: const LeaveHubScreen(),
      ),
      _ServiceTileData(
        icon: Icons.payments_outlined,
        label: 'Payments',
        color: AppColors.success,
        screen: const PaymentHubScreen(),
      ),
      _ServiceTileData(
        icon: Icons.trending_up_outlined,
        label: 'Sales Info',
        color: AppColors.warning,
        screen: const SalesInfoScreen(),
      ),
      _ServiceTileData(
        icon: Icons.my_location_outlined,
        label: 'Geo\nTracking',
        color: AppColors.error,
        screen: const GeoTrackingScreen(),
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(
            child: GradientScreenHeader(
              title: 'Employee Services',
              subtitle: 'Reports, leave, payments & more',
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.05,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final tile = tiles[index];
                  return FadeInUp(
                    delay: Duration(milliseconds: 80 * index),
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
  });

  final IconData icon;
  final String label;
  final Color color;
  final Widget screen;
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.tile});

  final _ServiceTileData tile;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      shadowColor: AppColors.shadow.withValues(alpha: 0.06),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => tile.screen),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadow.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: tile.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(tile.icon, color: tile.color, size: 24),
              ),
              const Spacer(),
              Text(
                tile.label,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    'Open',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: tile.color,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Icon(Icons.arrow_forward_rounded, size: 14, color: tile.color),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
