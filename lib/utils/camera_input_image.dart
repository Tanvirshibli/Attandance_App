import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Builds ML Kit [InputImage] from a live [CameraImage] frame.
class CameraInputImage {
  /// Last conversion failure reason (debug/support).
  static String? lastConversionFailure;

  static InputImage? fromCameraImage(
    CameraImage image,
    CameraController controller,
  ) {
    lastConversionFailure = null;
    final camera = controller.description;
    final rotation = _inputRotation(camera, controller);
    if (rotation == null) {
      lastConversionFailure = 'unsupported device orientation';
      return null;
    }

    if (Platform.isAndroid) {
      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == InputImageFormat.nv21 && image.planes.length == 1) {
        return InputImage.fromBytes(
          bytes: image.planes.first.bytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: rotation,
            format: InputImageFormat.nv21,
            bytesPerRow: image.planes.first.bytesPerRow,
          ),
        );
      }

      if (format == InputImageFormat.yuv420 && image.planes.length == 3) {
        try {
          final bytes = _yuv420ToNv21(image);
          return InputImage.fromBytes(
            bytes: bytes,
            metadata: InputImageMetadata(
              size: Size(image.width.toDouble(), image.height.toDouble()),
              rotation: rotation,
              format: InputImageFormat.nv21,
              bytesPerRow: image.width,
            ),
          );
        } catch (e) {
          lastConversionFailure = 'yuv420 conversion failed: $e';
          debugPrint('CameraInputImage: $lastConversionFailure');
          return null;
        }
      }

      lastConversionFailure =
          'unsupported Android format=${image.format.raw} planes=${image.planes.length}';
      return null;
    }

    if (Platform.isIOS && image.planes.length == 1) {
      return InputImage.fromBytes(
        bytes: image.planes.first.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.bgra8888,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    }

    lastConversionFailure = 'unsupported platform/format';
    return null;
  }

  /// Width/height for face bounding-box math after applying stream rotation.
  static ({int width, int height}) effectiveDimensions(
    CameraImage image,
    CameraController controller,
  ) {
    final degrees = _rotationDegrees(controller);
    if (degrees == 90 || degrees == 270) {
      return (width: image.height, height: image.width);
    }
    return (width: image.width, height: image.height);
  }

  static int? _rotationDegrees(CameraController controller) {
    final camera = controller.description;
    if (Platform.isIOS) {
      return camera.sensorOrientation;
    }
    if (Platform.isAndroid) {
      final rotationCompensation =
          _orientations[controller.value.deviceOrientation];
      if (rotationCompensation == null) return null;

      final sensorOrientation = camera.sensorOrientation;
      if (camera.lensDirection == CameraLensDirection.front) {
        return (sensorOrientation + rotationCompensation) % 360;
      }
      return (sensorOrientation - rotationCompensation + 360) % 360;
    }
    return 0;
  }

  static InputImageRotation? _inputRotation(
    CameraDescription camera,
    CameraController controller,
  ) {
    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    }
    if (Platform.isAndroid) {
      final degrees = _rotationDegrees(controller);
      if (degrees == null) return null;
      return InputImageRotationValue.fromRawValue(degrees);
    }
    return InputImageRotation.rotation0deg;
  }

  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  static Uint8List _yuv420ToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final nv21 = Uint8List(width * height + (width * height ~/ 2));
    var offset = 0;

    if (yPlane.bytesPerRow == width) {
      nv21.setRange(offset, offset + yPlane.bytes.length, yPlane.bytes);
      offset += yPlane.bytes.length;
    } else {
      for (var row = 0; row < height; row++) {
        nv21.setRange(
          offset,
          offset + width,
          yPlane.bytes.sublist(
            row * yPlane.bytesPerRow,
            row * yPlane.bytesPerRow + width,
          ),
        );
        offset += width;
      }
    }

    final uvHeight = height ~/ 2;
    final uvWidth = width ~/ 2;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;
    for (var row = 0; row < uvHeight; row++) {
      for (var col = 0; col < uvWidth; col++) {
        final uvIndex = row * uPlane.bytesPerRow + col * uvPixelStride;
        nv21[offset++] = vPlane.bytes[uvIndex];
        nv21[offset++] = uPlane.bytes[uvIndex];
      }
    }

    return nv21;
  }
}
