import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/theme.dart';
import '../models/geo_ping.dart';

enum MapTileStyle {
  standard(
    label: 'Standard',
    icon: Icons.map_outlined,
    urlTemplate: 'https://tile.openstreetmap.de/tiles/osmde/{z}/{x}/{y}.png',
    attribution: '© OpenStreetMap contributors · OSM DE',
  ),
  detailed(
    label: 'Detailed',
    icon: Icons.terrain_rounded,
    urlTemplate:
        'https://c.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png',
    attribution: '© OpenStreetMap contributors · CyclOSM',
  ),
  satellite(
    label: 'Satellite',
    icon: Icons.satellite_alt_outlined,
    urlTemplate:
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    attribution: 'Source: Esri, Maxar, Earthstar Geographics',
  );

  const MapTileStyle({
    required this.label,
    required this.icon,
    required this.urlTemplate,
    required this.attribution,
  });

  final String label;
  final IconData icon;
  final String urlTemplate;
  final String attribution;
}

/// OpenStreetMap live location panel used by Geo Tracking.
class LiveLocationMap extends StatefulWidget {
  const LiveLocationMap({
    super.key,
    required this.livePosition,
    this.accuracyMeters,
    this.history = const [],
    this.height = 300,
  });

  final LatLng? livePosition;
  final double? accuracyMeters;
  final List<GeoPing> history;
  final double height;

  /// Dhaka fallback when no GPS / last ping is available.
  static const LatLng fallbackCenter = LatLng(23.8103, 90.4125);

  @override
  LiveLocationMapState createState() => LiveLocationMapState();
}

class LiveLocationMapState extends State<LiveLocationMap> {
  static const double _liveZoom = 17;
  static const double _historyZoom = 15;

  final MapController _controller = MapController();
  bool _followLive = true;
  bool _hasCenteredOnce = false;
  MapTileStyle _tileStyle = MapTileStyle.standard;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LiveLocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.livePosition;
    if (next == null) return;

    if (!_hasCenteredOnce) {
      _hasCenteredOnce = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.move(next, _liveZoom);
      });
      return;
    }

    if (_followLive && next != oldWidget.livePosition) {
      _controller.move(next, _controller.camera.zoom);
    }
  }

  LatLng get _center {
    if (widget.livePosition != null) return widget.livePosition!;
    if (widget.history.isNotEmpty) {
      final ping = widget.history.first;
      return LatLng(ping.latitude, ping.longitude);
    }
    return LiveLocationMap.fallbackCenter;
  }

  void recenter() {
    final target = widget.livePosition ?? _center;
    setState(() => _followLive = true);
    _controller.move(target, widget.livePosition != null ? _liveZoom : _historyZoom);
  }

  void moveTo(LatLng point, {double? zoom}) {
    setState(() => _followLive = false);
    _controller.move(point, zoom ?? _liveZoom);
  }

  void _zoomBy(double delta) {
    final camera = _controller.camera;
    final next = (camera.zoom + delta).clamp(3.0, 19.0);
    setState(() => _followLive = false);
    _controller.move(camera.center, next);
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.livePosition;
    final accuracy = widget.accuracyMeters;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: AppColors.shadow.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              FlutterMap(
                mapController: _controller,
                options: MapOptions(
                  initialCenter: _center,
                  initialZoom: live != null ? _liveZoom : _historyZoom,
                  minZoom: 3,
                  maxZoom: 19,
                  onPositionChanged: (camera, hasGesture) {
                    if (hasGesture && _followLive) {
                      setState(() => _followLive = false);
                    }
                  },
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: _tileStyle.urlTemplate,
                    userAgentPackageName: 'com.pphl.employee_attendance',
                    maxNativeZoom: 19,
                  ),
                  if (live != null && accuracy != null && accuracy > 0)
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: live,
                          radius: accuracy.clamp(8, 120),
                          useRadiusInMeter: true,
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderColor:
                              AppColors.primary.withValues(alpha: 0.35),
                          borderStrokeWidth: 1.5,
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: [
                      ...widget.history.take(12).map((ping) {
                        return Marker(
                          point: LatLng(ping.latitude, ping.longitude),
                          width: 26,
                          height: 26,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.92),
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.place_rounded,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        );
                      }),
                      if (live != null)
                        Marker(
                          point: live,
                          width: 48,
                          height: 48,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.4),
                                  blurRadius: 14,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.navigation_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              Positioned(
                left: 12,
                top: 12,
                child: Material(
                  color: Colors.white.withValues(alpha: 0.96),
                  elevation: 4,
                  shadowColor: AppColors.shadow.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                  child: PopupMenuButton<MapTileStyle>(
                    tooltip: 'Map style',
                    initialValue: _tileStyle,
                    onSelected: (style) {
                      if (style == _tileStyle) return;
                      setState(() => _tileStyle = style);
                    },
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    itemBuilder: (context) {
                      return MapTileStyle.values.map((style) {
                        return PopupMenuItem<MapTileStyle>(
                          value: style,
                          child: Row(
                            children: [
                              Icon(
                                style.icon,
                                size: 18,
                                color: style == _tileStyle
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                              const SizedBox(width: 10),
                              Text(style.label),
                            ],
                          ),
                        );
                      }).toList();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _tileStyle.icon,
                            color: AppColors.primary,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _tileStyle.label,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.expand_more_rounded,
                            color: AppColors.textSecondary,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(
                    height: 36,
                    alignment: Alignment.bottomCenter,
                    padding: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.25),
                        ],
                      ),
                    ),
                    child: Text(
                      _tileStyle.attribution,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 12,
                bottom: 14,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Material(
                      color: Colors.white,
                      elevation: 4,
                      shadowColor: AppColors.shadow.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: () => _zoomBy(1),
                        borderRadius: BorderRadius.circular(14),
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(
                            Icons.add_rounded,
                            color: AppColors.textSecondary,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: Colors.white,
                      elevation: 4,
                      shadowColor: AppColors.shadow.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: () => _zoomBy(-1),
                        borderRadius: BorderRadius.circular(14),
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(
                            Icons.remove_rounded,
                            color: AppColors.textSecondary,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: Colors.white,
                      elevation: 4,
                      shadowColor: AppColors.shadow.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: recenter,
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Icon(
                            Icons.my_location_rounded,
                            color: _followLive
                                ? AppColors.primary
                                : AppColors.textSecondary,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (live == null)
                Positioned(
                  left: 12,
                  top: 60,
                  right: 56,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.shadow.withValues(alpha: 0.12),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Waiting for live GPS…',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
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
