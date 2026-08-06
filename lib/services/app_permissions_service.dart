import 'package:permission_handler/permission_handler.dart';

class AppPermissionItem {
  const AppPermissionItem({
    required this.id,
    required this.label,
    required this.description,
    required this.permission,
  });

  final String id;
  final String label;
  final String description;
  final Permission permission;
}

enum AppPermissionRequestOutcome {
  granted,
  denied,
  permanentlyDenied,
}

class AppPermissionRequestResult {
  const AppPermissionRequestResult({
    required this.outcome,
    this.failedPermissionId,
  });

  final AppPermissionRequestOutcome outcome;
  final String? failedPermissionId;

  bool get isSuccess => outcome == AppPermissionRequestOutcome.granted;
}

class AppPermissionsService {
  AppPermissionsService._();
  static final AppPermissionsService instance = AppPermissionsService._();

  static const List<AppPermissionItem> requiredItems = [
    AppPermissionItem(
      id: 'notification',
      label: 'Notifications',
      description: 'Geo wake alerts and tracking status',
      permission: Permission.notification,
    ),
    AppPermissionItem(
      id: 'camera',
      label: 'Camera',
      description: 'Face check-in and face registration',
      permission: Permission.camera,
    ),
    AppPermissionItem(
      id: 'location_when_in_use',
      label: 'Location (while using app)',
      description: 'Attendance punches and live map',
      permission: Permission.locationWhenInUse,
    ),
    AppPermissionItem(
      id: 'location_always',
      label: 'Location (all the time)',
      description: 'Background geo tracking',
      permission: Permission.locationAlways,
    ),
  ];

  Future<bool> _isItemGranted(AppPermissionItem item) async {
    final status = await item.permission.status;
    return status.isGranted || status.isLimited;
  }

  Future<Map<String, bool>> statusSnapshot() async {
    final map = <String, bool>{};
    for (final item in requiredItems) {
      map[item.id] = await _isItemGranted(item);
    }
    return map;
  }

  Future<bool> areAllGranted() async {
    final snapshot = await statusSnapshot();
    return snapshot.values.every((granted) => granted);
  }

  Future<bool> hasPermanentlyDenied() async {
    for (final item in requiredItems) {
      final status = await item.permission.status;
      if (status.isPermanentlyDenied) {
        return true;
      }
    }
    return false;
  }

  Future<AppPermissionRequestResult> requestNotifications() async {
    final item = requiredItems.firstWhere((i) => i.id == 'notification');
    var status = await item.permission.status;
    if (status.isGranted || status.isLimited) {
      return const AppPermissionRequestResult(
        outcome: AppPermissionRequestOutcome.granted,
      );
    }
    if (status.isPermanentlyDenied) {
      return const AppPermissionRequestResult(
        outcome: AppPermissionRequestOutcome.permanentlyDenied,
        failedPermissionId: 'notification',
      );
    }

    status = await item.permission.request();
    if (status.isGranted || status.isLimited) {
      return const AppPermissionRequestResult(
        outcome: AppPermissionRequestOutcome.granted,
      );
    }
    if (status.isPermanentlyDenied) {
      return const AppPermissionRequestResult(
        outcome: AppPermissionRequestOutcome.permanentlyDenied,
        failedPermissionId: 'notification',
      );
    }
    return const AppPermissionRequestResult(
      outcome: AppPermissionRequestOutcome.denied,
      failedPermissionId: 'notification',
    );
  }

  Future<AppPermissionRequestResult> requestRemainingPermissions() async {
    final camera = requiredItems.firstWhere((i) => i.id == 'camera');
    var status = await camera.permission.request();
    if (!status.isGranted) {
      return AppPermissionRequestResult(
        outcome: status.isPermanentlyDenied
            ? AppPermissionRequestOutcome.permanentlyDenied
            : AppPermissionRequestOutcome.denied,
        failedPermissionId: camera.id,
      );
    }

    final whenInUse =
        requiredItems.firstWhere((i) => i.id == 'location_when_in_use');
    status = await whenInUse.permission.request();
    if (!status.isGranted && !status.isLimited) {
      return AppPermissionRequestResult(
        outcome: status.isPermanentlyDenied
            ? AppPermissionRequestOutcome.permanentlyDenied
            : AppPermissionRequestOutcome.denied,
        failedPermissionId: whenInUse.id,
      );
    }

    final always = requiredItems.firstWhere((i) => i.id == 'location_always');
    status = await always.permission.request();
    if (!status.isGranted && !status.isLimited) {
      return AppPermissionRequestResult(
        outcome: status.isPermanentlyDenied
            ? AppPermissionRequestOutcome.permanentlyDenied
            : AppPermissionRequestOutcome.denied,
        failedPermissionId: always.id,
      );
    }

    return const AppPermissionRequestResult(
      outcome: AppPermissionRequestOutcome.granted,
    );
  }

  Future<void> openSystemSettings() => openAppSettings();
}
