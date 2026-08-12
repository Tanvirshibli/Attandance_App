import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// One-shot location + reverse geocode for Farm & Dealer create forms.
class MarketingLocationSnapshot {
  const MarketingLocationSnapshot({
    required this.latitude,
    required this.longitude,
    this.address,
    this.division,
    this.district,
    this.upazila,
    this.unionName,
    this.village,
  });

  final double latitude;
  final double longitude;
  final String? address;
  final String? division;
  final String? district;
  final String? upazila;
  final String? unionName;
  final String? village;
}

class MarketingLocationHelper {
  MarketingLocationHelper._();

  static Future<MarketingLocationSnapshot?> capture({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final status = await Permission.locationWhenInUse.request();
    if (!status.isGranted) return null;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    final position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: timeout,
      ),
    );

    String? address;
    String? division;
    String? district;
    String? upazila;
    String? unionName;
    String? village;

    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        division = _nz(p.administrativeArea);
        district = _nz(p.subAdministrativeArea) ?? _nz(p.locality);
        upazila = _nz(p.subLocality) ?? _nz(p.locality);
        unionName = _nz(p.thoroughfare) ?? _nz(p.subThoroughfare);
        village = _nz(p.name) ?? _nz(p.subLocality);
        address = [
          p.street,
          p.subLocality,
          p.locality,
          p.subAdministrativeArea,
          p.administrativeArea,
          p.country,
        ].whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).join(', ');
        if (address.isEmpty) address = null;
      }
    } catch (_) {}

    return MarketingLocationSnapshot(
      latitude: position.latitude,
      longitude: position.longitude,
      address: address,
      division: division,
      district: district,
      upazila: upazila,
      unionName: unionName,
      village: village,
    );
  }

  static String? _nz(String? v) {
    final t = v?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }
}
