import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import '../models/vehicle_models.dart';
import '../widgets/gradient_screen_header.dart';
import '../widgets/section_card.dart';
import 'vehicle_maintenance_screen.dart';
import 'vehicle_trip_list_screen.dart';

class VehicleHubScreen extends StatelessWidget {
  const VehicleHubScreen({super.key, required this.vehicle});

  final VehicleSummary vehicle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: GradientScreenHeader(
              title: vehicle.displayPlate,
              subtitle: 'Maintenance and trips',
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _hubCard(
                  context,
                  delay: 0,
                  icon: Icons.build_outlined,
                  title: 'Maintenance',
                  subtitle: 'Jobs, parts and workshop history',
                  color: AppColors.warning,
                  screen: VehicleMaintenanceScreen(vehicle: vehicle),
                ),
                _hubCard(
                  context,
                  delay: 80,
                  icon: Icons.route_outlined,
                  title: 'Trips',
                  subtitle: 'All trips for this vehicle',
                  color: AppColors.info,
                  screen: VehicleTripListScreen(vehicle: vehicle),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hubCard(
    BuildContext context, {
    required int delay,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Widget screen,
  }) {
    return FadeInUp(
      delay: Duration(milliseconds: delay),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SectionCard(
          padding: EdgeInsets.zero,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => screen),
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
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: AppColors.textSecondary,
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
  }
}
