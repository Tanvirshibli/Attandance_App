import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/theme.dart';
import '../models/geo_ping.dart';

enum MapTileStyle {
  standard(
    label: 'Standard',
    icon: Icons.map_outlined,
    mapType: MapType.normal,
    attribution: '© Google',
  ),
  detailed(
    label: 'Detailed',
    icon: Icons.terrain_rounded,
    mapType: MapType.terrain,
    attribution: '© Google',
  ),
  satellite(
    label: 'Satellite',
    icon: Icons.satellite_alt_outlined,
    mapType: MapType.hybrid,
    attribution: '© Google',
  );

  const MapTileStyle({
    required this.label,
    required this.icon,
    required this.mapType,
    required this.attribution,
  });

  final String label;
  final IconData icon;
  final MapType mapType;
  final String attribution;
}

/// Google Maps live location panel used by Geo Tracking.
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

  GoogleMapController? _controller;
  bool _followLive = true;
  bool _hasCenteredOnce = false;
  bool _programmaticMove = false;
  double _currentZoom = _historyZoom;
  MapTileStyle _tileStyle = MapTileStyle.standard;

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
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
        if (mounted) _moveCamera(next, _liveZoom);
      });
      return;
    }

    if (_followLive && next != oldWidget.livePosition) {
      _moveCamera(next, _currentZoom);
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
    _moveCamera(
      target,
      widget.livePosition != null ? _liveZoom : _historyZoom,
    );
  }

  void moveTo(LatLng point, {double? zoom}) {
    setState(() => _followLive = false);
    _moveCamera(point, zoom ?? _liveZoom);
  }

  Future<void> _moveCamera(LatLng target, double zoom) async {
    final controller = _controller;
    if (controller == null) return;
    _programmaticMove = true;
    _currentZoom = zoom;
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(target, zoom),
    );
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      _programmaticMove = false;
    });
  }

  Future<void> _zoomBy(double delta) async {
    final next = (_currentZoom + delta).clamp(3.0, 20.0);
    setState(() => _followLive = false);
    _currentZoom = next;
    final controller = _controller;
    if (controller == null) return;
    _programmaticMove = true;
    await controller.animateCamera(CameraUpdate.zoomTo(next));
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      _programmaticMove = false;
    });
  }

  Set<Marker> get _markers {
    final markers = <Marker>{};
    var index = 0;
    for (final ping in widget.history.take(12)) {
      markers.add(
        Marker(
          markerId: MarkerId('history-$index'),
          position: LatLng(ping.latitude, ping.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueCyan,
          ),
          infoWindow: InfoWindow(
            title: ping.address ?? 'Recent ping',
          ),
          zIndexInt: index,
        ),
      );
      index++;
    }
    final live = widget.livePosition;
    if (live != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('live'),
          position: live,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: const InfoWindow(title: 'You'),
          zIndexInt: 100,
        ),
      );
    }
    return markers;
  }

  Set<Circle> get _circles {
    final live = widget.livePosition;
    final accuracy = widget.accuracyMeters;
    if (live == null || accuracy == null || accuracy <= 0) {
      return const <Circle>{};
    }
    return {
      Circle(
        circleId: const CircleId('accuracy'),
        center: live,
        radius: accuracy.clamp(8, 120),
        fillColor: AppColors.primary.withValues(alpha: 0.12),
        strokeColor: AppColors.primary.withValues(alpha: 0.35),
        strokeWidth: 2,
      ),
    };
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;
    final live = widget.livePosition;
    if (live != null) {
      _hasCenteredOnce = true;
      _moveCamera(live, _liveZoom);
    }
  }

  void _onCameraMoveStarted() {
    if (!_programmaticMove && _followLive) {
      setState(() => _followLive = false);
    }
  }

  void _onCameraMove(CameraPosition position) {
    _currentZoom = position.zoom;
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.livePosition;

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
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _center,
                  zoom: live != null ? _liveZoom : _historyZoom,
                ),
                mapType: _tileStyle.mapType,
                markers: _markers,
                circles: _circles,
                onMapCreated: _onMapCreated,
                onCameraMoveStarted: _onCameraMoveStarted,
                onCameraMove: _onCameraMove,
                minMaxZoomPreference: const MinMaxZoomPreference(3, 20),
                compassEnabled: false,
                rotateGesturesEnabled: false,
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                buildingsEnabled: true,
                indoorViewEnabled: true,
                trafficEnabled: false,
                liteModeEnabled: false,
                gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                  Factory<OneSequenceGestureRecognizer>(
                    () => EagerGestureRecognizer(),
                  ),
                },
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
