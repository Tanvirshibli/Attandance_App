import 'dart:async';

import 'package:camera/camera.dart';

/// Caches camera enumeration so the capture screens do not pay for
/// `availableCameras()` on every open.
///
/// The list is stable for the life of the process, so enumerating once at
/// start-up takes a visible delay off the check-in screen's critical path.
class CameraPrewarm {
  CameraPrewarm._();

  static List<CameraDescription>? _cameras;

  /// The camera list, enumerated once and reused.
  static Future<List<CameraDescription>> cameras() async =>
      _cameras ??= await availableCameras();

  /// Kick off enumeration in the background. Best-effort — a failure just means
  /// the capture screen enumerates the usual way.
  static void warm() {
    unawaited(cameras().catchError((_) => const <CameraDescription>[]));
  }
}
