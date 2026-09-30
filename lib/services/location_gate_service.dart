import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Why location is unavailable.
///
/// The two causes are deliberately distinct. "Location is switched off" and
/// "the app is not allowed to use location" are different problems with
/// different fixes in different places in Android Settings, and telling a user
/// to check the wrong one sends them away without solving anything.
enum LocationGateStatus {
  ok,
  serviceDisabled,
  permissionDenied,
  permanentlyDenied,
}

class LocationGateResult {
  const LocationGateResult(this.status);

  final LocationGateStatus status;

  bool get isBlocking => status != LocationGateStatus.ok;

  /// Whether opening system settings could plausibly help.
  bool get needsSettings => status != LocationGateStatus.ok;

  /// A sentence naming the actual problem, for the gate UI.
  String get reason => switch (status) {
    LocationGateStatus.ok => 'Location is on.',
    LocationGateStatus.serviceDisabled =>
      'Location is turned off on this device.',
    LocationGateStatus.permissionDenied =>
      'PPHL Attendance has not been allowed to use your location.',
    LocationGateStatus.permanentlyDenied =>
      'Location permission was permanently denied for this app.',
  };

  /// What the user has to do about it.
  String get remedy => switch (status) {
    LocationGateStatus.ok => '',
    LocationGateStatus.serviceDisabled =>
      'Turn Location on, then come back.',
    LocationGateStatus.permissionDenied =>
      'Allow location access for PPHL Attendance, then come back.',
    LocationGateStatus.permanentlyDenied =>
      'Location access was blocked. Re-enable it in app settings, then come back.',
  };

  /// Which Settings screen actually contains the fix.
  bool get opensLocationSettings => status == LocationGateStatus.serviceDisabled;
}

/// Checks whether the app can currently capture a location fix.
///
/// Deliberately separate from `AppPermissionsService`, which asks for the OS
/// permission once at first launch. That permission can be granted and still be
/// useless: the user can switch the device's location service off afterwards,
/// and then every capture fails silently. `GeoTrackingService` skips its pings
/// when the service is off, and a punch fails at the point the user is trying
/// to clock in — long after they could have been told.
class LocationGateService {
  const LocationGateService();

  /// One round trip to the platform, no permission prompts.
  ///
  /// Only reports on what is already granted; it never asks for anything, so it
  /// is safe to call on every resume.
  Future<LocationGateResult> check() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationGateResult(LocationGateStatus.serviceDisabled);
    }

    // locationAlways is checked as well as locationWhenInUse because the app
    // tracks in the background; a user who revoked "all the time" but kept
    // "while using the app" would otherwise pass the gate and then silently
    // stop producing background pings.
    final whenInUse = await Permission.locationWhenInUse.status;
    final always = await Permission.locationAlways.status;

    if (whenInUse.isGranted || whenInUse.isLimited || always.isGranted) {
      return const LocationGateResult(LocationGateStatus.ok);
    }

    if (whenInUse.isPermanentlyDenied || always.isPermanentlyDenied) {
      return const LocationGateResult(LocationGateStatus.permanentlyDenied);
    }

    return const LocationGateResult(LocationGateStatus.permissionDenied);
  }

  /// Sends the user to the screen that actually holds the fix.
  Future<void> openSettings(LocationGateResult result) async {
    if (result.opensLocationSettings) {
      await Geolocator.openLocationSettings();
      return;
    }
    await openAppSettings();
  }
}