import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/theme.dart';
import '../models/geo_ping.dart';
import '../services/fcm_wake_handler.dart';
import '../services/geo_tracking_service.dart';
import '../widgets/gradient_screen_header.dart';
import '../widgets/live_location_map.dart';

class GeoTrackingScreen extends StatefulWidget {
  const GeoTrackingScreen({super.key});

  @override
  State<GeoTrackingScreen> createState() => _GeoTrackingScreenState();
}

class _GeoTrackingScreenState extends State<GeoTrackingScreen> {
  final GeoTrackingService _geoService = GeoTrackingService();
  final GlobalKey<LiveLocationMapState> _mapKey =
      GlobalKey<LiveLocationMapState>();

  bool _enabled = false;
  bool _featureEnabled = true;
  bool _isLoading = true;
  bool _capturing = false;
  bool _needsLocationPermission = false;
  String _permissionSummary = '';
  GeoPing? _lastPing;
  int _pendingCount = 0;
  int _intervalMinutes = 5;
  List<GeoPing> _history = const [];

  LatLng? _livePosition;
  double? _accuracyMeters;
  StreamSubscription<Position>? _positionSub;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _geoService.ensureEnabledIfAllowed();
    await _refresh();
    await _startLiveLocation();
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    final featureOn = await _geoService.isGeoFeatureEnabled();
    final enabled = await _geoService.isEnabled();
    final permission = await _geoService.permissionSummary();
    final lastPing = await _geoService.getLastPing();
    final pending = await _geoService.pendingUploadCount();
    final interval = await _geoService.configuredIntervalMinutes();
    final history = await _geoService.fetchHistory(limit: 15);
    if (!mounted) return;
    setState(() {
      _enabled = featureOn && enabled;
      _featureEnabled = featureOn;
      _permissionSummary = permission;
      _lastPing = lastPing;
      _pendingCount = pending;
      _intervalMinutes = interval;
      _history = history;
      _isLoading = false;
      if (_livePosition == null && lastPing != null) {
        _livePosition = LatLng(lastPing.latitude, lastPing.longitude);
      }
    });
  }

  Future<void> _startLiveLocation() async {
    final whenInUse = await Permission.locationWhenInUse.status;
    if (!whenInUse.isGranted) {
      if (!mounted) return;
      setState(() => _needsLocationPermission = true);
      return;
    }

    setState(() => _needsLocationPermission = false);

    try {
      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted) return;
      setState(() {
        _livePosition = LatLng(current.latitude, current.longitude);
        _accuracyMeters = current.accuracy;
      });
    } catch (_) {}

    await _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 8,
      ),
    ).listen((position) {
      if (!mounted) return;
      setState(() {
        _livePosition = LatLng(position.latitude, position.longitude);
        _accuracyMeters = position.accuracy;
      });
    });
  }

  Future<void> _requestLivePermission() async {
    final status = await _geoService.requestPermissions();
    if (status.isGranted || status.isLimited) {
      await _geoService.ensureEnabledIfAllowed();
      await _startLiveLocation();
      await _refresh();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permission is required for the live map.'),
        ),
      );
    }
  }

  Future<void> _captureNow() async {
    setState(() => _capturing = true);
    try {
      await _geoService.captureAndQueue(source: 'manual');
      await _refresh();
      if (_lastPing != null) {
        _mapKey.currentState?.moveTo(
          LatLng(_lastPing!.latitude, _lastPing!.longitude),
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
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
              subtitle: 'Live map · every $_intervalMinutes min',
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_needsLocationPermission) _permissionBanner(),
                LiveLocationMap(
                  key: _mapKey,
                  livePosition: _livePosition,
                  accuracyMeters: _accuracyMeters,
                  history: _history,
                  height: 300,
                ),
                const SizedBox(height: 14),
                _trackingCard(),
                const SizedBox(height: 12),
                _statusChips(),
                const SizedBox(height: 16),
                _actionRow(),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: openAppSettings,
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: Text(
                      'Battery & app settings',
                      style: GoogleFonts.poppins(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _historySection(),
                if (_isLoading) ...[
                  const SizedBox(height: 16),
                  const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _permissionBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: _requestLivePermission,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.location_off_rounded,
                    color: AppColors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Enable location to see yourself on the map',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  'Allow',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _trackingCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _enabled
              ? [
                  AppColors.primary.withValues(alpha: 0.12),
                  AppColors.accent.withValues(alpha: 0.08),
                ]
              : [
                  AppColors.surface,
                  AppColors.surface,
                ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _enabled
              ? AppColors.primary.withValues(alpha: 0.25)
              : AppColors.divider,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: _enabled
                  ? AppColors.primaryGradient
                  : LinearGradient(
                      colors: [
                        AppColors.textHint.withValues(alpha: 0.35),
                        AppColors.textHint.withValues(alpha: 0.2),
                      ],
                    ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _enabled ? Icons.radar_rounded : Icons.location_disabled_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _statusTitle,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _statusSubtitle,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _statusTitle {
    if (!_featureEnabled) return 'Tracking unavailable';
    return _enabled ? 'Tracking on' : 'Tracking off';
  }

  String get _statusSubtitle {
    if (!_featureEnabled) {
      return 'Geo tracking is disabled by server config';
    }
    if (_permissionSummary.isNotEmpty) return _permissionSummary;
    return _enabled
        ? 'Background location active · uploads to ZKTeco'
        : 'Background location required';
  }

  Widget _statusChips() {
    final fcmShort = FcmWakeHandler.isConfigured ? 'FCM ready' : 'FCM scaffold';
    final chips = <_ChipData>[
      _ChipData(Icons.schedule_rounded, 'Every $_intervalMinutes min'),
      _ChipData(Icons.cloud_upload_outlined, '$_pendingCount pending'),
      const _ChipData(Icons.work_outline_rounded, 'WorkManager'),
      _ChipData(Icons.notifications_none_rounded, fcmShort),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips.map((chip) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(chip.icon, size: 15, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                chip.label,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _actionRow() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _capturing ? null : _captureNow,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: _capturing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.my_location_rounded),
        label: Text(
          _capturing ? 'Capturing…' : 'Capture Now',
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _historySection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Recent pings',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_lastPing != null)
                Text(
                  DateFormat('hh:mm a').format(_lastPing!.capturedAt),
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: AppColors.textHint,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_history.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'No history yet. Capture a ping or enable tracking.',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            )
          else
            ..._history.take(10).map(_historyTile),
        ],
      ),
    );
  }

  Widget _historyTile(GeoPing ping) {
    final point = LatLng(ping.latitude, ping.longitude);
    return InkWell(
      onTap: () => _mapKey.currentState?.moveTo(point),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.place_rounded,
                size: 18,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('dd MMM · hh:mm a').format(ping.capturedAt),
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ping.address ??
                        '${ping.latitude.toStringAsFixed(4)}, ${ping.longitude.toStringAsFixed(4)}',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.textHint, size: 20),
          ],
        ),
      ),
    );
  }
}

class _ChipData {
  const _ChipData(this.icon, this.label);
  final IconData icon;
  final String label;
}
