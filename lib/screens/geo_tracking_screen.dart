import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../widgets/ui/ui.dart' as ui;
import '../models/geo_ping.dart';
import '../services/fcm_wake_handler.dart';
import '../services/geo_tracking_service.dart';
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
  bool _mapFullscreen = false;

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
    return PopScope(
      canPop: !_mapFullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !_mapFullscreen) return;
        setState(() => _mapFullscreen = false);
      },
      child: Scaffold(
        backgroundColor: ui.AppColors.canvas,
        body: _mapFullscreen ? _fullscreenMap() : _scrollBody(),
      ),
    );
  }

  Widget _mapPanel({required bool expand}) {
    return LiveLocationMap(
      key: _mapKey,
      livePosition: _livePosition,
      accuracyMeters: _accuracyMeters,
      history: _history,
      height: 300,
      expand: expand,
      isFullscreen: _mapFullscreen,
      onToggleFullscreen: () {
        setState(() => _mapFullscreen = !_mapFullscreen);
      },
    );
  }

  Widget _fullscreenMap() {
    return SafeArea(
      child: SizedBox.expand(child: _mapPanel(expand: true)),
    );
  }

  Widget _scrollBody() {
    return CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: ui.AppHeader(
              title: 'Geo tracking',
              subtitle: 'Live map · every $_intervalMinutes min',
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              ui.AppSpace.gutter,
              ui.AppSpace.xs,
              ui.AppSpace.gutter,
              ui.AppSpace.xl,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_needsLocationPermission) _permissionBanner(),
                _mapPanel(expand: false),
                const SizedBox(height: ui.AppSpace.md),
                _trackingCard(),
                const SizedBox(height: ui.AppSpace.sm),
                _statusChips(),
                const SizedBox(height: ui.AppSpace.md),
                _actionRow(),
                const SizedBox(height: ui.AppSpace.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: openAppSettings,
                    icon: ui.AppIcon(
                      ui.AppIcons.key,
                      size: 16,
                      color: ui.AppColors.inkMuted,
                    ),
                    label: Text(
                      'Battery & app settings',
                      style: ui.AppType.meta
                          .copyWith(color: ui.AppColors.inkMuted),
                    ),
                  ),
                ),
                const SizedBox(height: ui.AppSpace.xs),
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
      );
  }

  Widget _permissionBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: ui.AppSpace.sm),
      child: Material(
        color: ui.AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ui.AppRadius.lg),
        child: InkWell(
          onTap: _requestLivePermission,
          borderRadius: BorderRadius.circular(ui.AppRadius.lg),
          child: Padding(
            padding: const EdgeInsets.all(ui.AppSpace.sm),
            child: Row(
              children: [
                ui.AppIcon(
                  ui.AppIcons.pin,
                  size: 18,
                  color: ui.AppColors.warning,
                ),
                const SizedBox(width: ui.AppSpace.xs),
                Expanded(
                  child: Text(
                    'Enable location to see yourself on the map',
                    style: ui.AppType.meta.copyWith(
                      color: ui.AppColors.ink,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  'Allow',
                  style: ui.AppType.meta.copyWith(
                    color: ui.AppColors.mGeo,
                    fontWeight: FontWeight.w700,
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
    final accent = _enabled ? ui.AppColors.mGeo : ui.AppColors.inkFaint;
    return ui.AppCard(
      padding: const EdgeInsets.all(ui.AppSpace.md),
      child: Row(
        children: [
          ui.AppIconTile(
            icon: _enabled ? ui.AppIcons.geo : ui.AppIcons.eyeOff,
            color: accent,
            size: ui.AppIconTileSize.large,
            filled: _enabled,
            semanticLabel: _statusTitle,
          ),
          const SizedBox(width: ui.AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _statusTitle,
                  style: ui.AppType.h3.copyWith(color: ui.AppColors.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  _statusSubtitle,
                  style: ui.AppType.meta
                      .copyWith(color: ui.AppColors.inkMuted),
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
      _ChipData(ui.AppIcons.clock, 'Every $_intervalMinutes min'),
      _ChipData(ui.AppIcons.upload, '$_pendingCount pending'),
      const _ChipData(PhosphorIconsDuotone.batteryCharging, 'WorkManager'),
      _ChipData(ui.AppIcons.bell, fcmShort),
    ];

    return Wrap(
      spacing: ui.AppSpace.xs,
      runSpacing: ui.AppSpace.xs,
      children: chips.map((chip) {
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: ui.AppSpace.sm,
            vertical: ui.AppSpace.xs,
          ),
          decoration: BoxDecoration(
            color: ui.AppColors.surface,
            borderRadius: BorderRadius.circular(ui.AppRadius.pill),
            border: Border.all(color: ui.AppColors.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ui.AppIcon(
                chip.icon,
                size: 14,
                color: ui.AppColors.mGeo,
                secondaryOpacity: 0.5,
              ),
              const SizedBox(width: ui.AppSpace.xxs + 2),
              Text(
                chip.label,
                style: ui.AppType.micro
                    .copyWith(color: ui.AppColors.inkMuted),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _actionRow() {
    return ui.AppButton(
      label: _capturing ? 'Capturing…' : 'Capture now',
      icon: ui.AppIcons.target,
      busy: _capturing,
      accent: ui.AppColors.mGeo,
      onPressed: _capturing ? null : _captureNow,
    );
  }

  Widget _historySection() {
    return ui.AppCard(
      padding: const EdgeInsets.all(ui.AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Expanded, not AppSectionTitle alone: the timestamp is a sibling
              // in this Row, so the title needs a bounded share of the width.
              Expanded(
                child: ui.AppSectionTitle(
                  title: 'Recent pings',
                  accent: ui.AppColors.mGeo,
                ),
              ),
              if (_lastPing != null)
                Text(
                  DateFormat('hh:mm a').format(_lastPing!.capturedAt),
                  style: ui.AppType.micro
                      .copyWith(color: ui.AppColors.inkFaint),
                ),
            ],
          ),
          const SizedBox(height: ui.AppSpace.xs),
          if (_history.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: ui.AppSpace.sm),
              child: Text(
                'No history yet. Capture a ping or enable tracking.',
                style: ui.AppType.meta
                    .copyWith(color: ui.AppColors.inkMuted),
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
      borderRadius: BorderRadius.circular(ui.AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ui.AppSpace.xs + 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ui.AppIconTile(
              icon: ui.AppIcons.pin,
              color: ui.AppColors.mGeo,
              size: ui.AppIconTileSize.small,
            ),
            const SizedBox(width: ui.AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DateFormat('dd MMM · hh:mm a').format(ping.capturedAt),
                    style: ui.AppType.h3.copyWith(color: ui.AppColors.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ping.address ??
                        '${ping.latitude.toStringAsFixed(4)}, ${ping.longitude.toStringAsFixed(4)}',
                    style: ui.AppType.micro
                        .copyWith(color: ui.AppColors.inkFaint),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            ui.AppIcon(
              ui.AppIcons.chevron,
              size: 16,
              color: ui.AppColors.inkFaint,
            ),
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
