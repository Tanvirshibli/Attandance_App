import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/app_config.dart';
import '../config/theme.dart';
import '../models/geo_ping.dart';
import '../services/geo_tracking_service.dart';
import '../widgets/gradient_screen_header.dart';
import '../widgets/section_card.dart';

class GeoTrackingScreen extends StatefulWidget {
  const GeoTrackingScreen({super.key});

  @override
  State<GeoTrackingScreen> createState() => _GeoTrackingScreenState();
}

class _GeoTrackingScreenState extends State<GeoTrackingScreen> {
  final GeoTrackingService _geoService = GeoTrackingService();

  bool _enabled = false;
  bool _isLoading = true;
  String _permissionSummary = '';
  GeoPing? _lastPing;
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    final enabled = await _geoService.isEnabled();
    final permission = await _geoService.permissionSummary();
    final lastPing = await _geoService.getLastPing();
    final pending = await _geoService.pendingUploadCount();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _permissionSummary = permission;
      _lastPing = lastPing;
      _pendingCount = pending;
      _isLoading = false;
    });
  }

  Future<void> _toggle(bool value) async {
    if (value) {
      final status = await _geoService.requestPermissions();
      if (!status.isGranted && !status.isLimited) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission is required for geo tracking.'),
          ),
        );
        return;
      }
    }

    await _geoService.setEnabled(value);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: GradientScreenHeader(
              title: 'Geo Tracking',
              subtitle:
                  'Background location every ${AppConfig.geoTrackingIntervalMinutes} minutes',
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                SectionCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Enable Tracking',
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Sends location while app is closed (when permitted)',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _enabled,
                        onChanged: _isLoading ? null : _toggle,
                        activeTrackColor: AppColors.primary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoRow(Icons.security_outlined, 'Permission', _permissionSummary),
                      const Divider(height: 20),
                      _infoRow(
                        Icons.schedule_rounded,
                        'Interval',
                        'Every ${AppConfig.geoTrackingIntervalMinutes} minutes',
                      ),
                      const Divider(height: 20),
                      _infoRow(
                        Icons.cloud_upload_outlined,
                        'Pending uploads',
                        '$_pendingCount',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Last Ping',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_lastPing == null)
                        Text(
                          'No location captured yet.',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        )
                      else ...[
                        Text(
                          DateFormat('dd MMM yyyy, hh:mm a')
                              .format(_lastPing!.capturedAt),
                          style: GoogleFonts.poppins(fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_lastPing!.latitude.toStringAsFixed(5)}, ${_lastPing!.longitude.toStringAsFixed(5)}',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (_lastPing!.address != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            _lastPing!.address!,
                            style: GoogleFonts.poppins(fontSize: 12),
                          ),
                        ],
                      ],
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await _geoService.captureAndQueue();
                          await _refresh();
                        },
                        icon: const Icon(Icons.my_location_rounded),
                        label: const Text('Capture Now'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Battery & reliability',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'For best results, disable battery optimization for this app. '
                        'True background tracking (app closed) requires FCM + Workmanager — coming in a future release.',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: openAppSettings,
                        child: const Text('Open App Settings'),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.poppins(fontSize: 13),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
