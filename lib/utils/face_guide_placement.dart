import 'dart:math';
import 'dart:ui';

import '../l10n/face_capture_strings.dart';
import '../widgets/face_capture_stage.dart';

/// Maps a live face box onto the on-screen rounded frame (BoxFit.cover + optional mirror).
class FaceGuidePlacement {
  static const double minOvalHeightFill = 0.70;
  static const double maxOvalHeightFill = 1.15;
  static const double ovalInsetFraction = 0.12;
  static const double angledInsetFraction = 0.04;

  /// Cover-fit [imageRect] from [imageSize] onto [previewSize].
  static Rect mapImageRectToPreview({
    required Rect imageRect,
    required Size imageSize,
    required Size previewSize,
    bool mirrorX = false,
  }) {
    if (imageSize.width <= 0 ||
        imageSize.height <= 0 ||
        previewSize.width <= 0 ||
        previewSize.height <= 0) {
      return Rect.zero;
    }

    var rect = imageRect;
    if (mirrorX) {
      rect = Rect.fromLTRB(
        imageSize.width - imageRect.right,
        imageRect.top,
        imageSize.width - imageRect.left,
        imageRect.bottom,
      );
    }

    final scale = max(
      previewSize.width / imageSize.width,
      previewSize.height / imageSize.height,
    );
    final dx = (previewSize.width - imageSize.width * scale) / 2;
    final dy = (previewSize.height - imageSize.height * scale) / 2;
    return Rect.fromLTWH(
      rect.left * scale + dx,
      rect.top * scale + dy,
      rect.width * scale,
      rect.height * scale,
    );
  }

  static Rect insetGuideRect(
    Size previewSize, {
    double? insetFraction,
  }) {
    final fraction = insetFraction ?? ovalInsetFraction;
    final frame = faceGuideRect(previewSize);
    return Rect.fromCenter(
      center: frame.center,
      width: frame.width * (1 - fraction * 2),
      height: frame.height * (1 - fraction * 2),
    );
  }

  /// Null when the face fills and sits inside the frame; otherwise coaching text.
  /// [angled] uses a looser center inset so yaw/pitch poses are not treated as off-guide.
  /// Defaults to English, which keeps the face-registration screen on English.
  static String? issue({
    required Rect faceBox,
    required Size imageSize,
    required Size previewSize,
    bool mirrorX = false,
    bool angled = false,
    FaceCaptureStrings strings = FaceCaptureStrings.english,
  }) {
    if (imageSize.width <= 0 ||
        imageSize.height <= 0 ||
        previewSize.width <= 0 ||
        previewSize.height <= 0 ||
        faceBox.isEmpty) {
      return strings.holdStillWhileFocusing;
    }

    final mapped = mapImageRectToPreview(
      imageRect: faceBox,
      imageSize: imageSize,
      previewSize: previewSize,
      mirrorX: mirrorX,
    );
    final frame = faceGuideRect(previewSize);
    if (frame.height <= 0) {
      return strings.holdStillWhileFocusing;
    }

    final heightFill = mapped.height / frame.height;
    if (heightFill < minOvalHeightFill) {
      return strings.moveCloser;
    }
    if (heightFill > maxOvalHeightFill) {
      return strings.moveBack;
    }

    final inset = insetGuideRect(
      previewSize,
      insetFraction: angled ? angledInsetFraction : ovalInsetFraction,
    );
    final centerInside = buildFaceGuidePath(inset).contains(mapped.center);
    if (!centerInside) {
      return strings.centerFace;
    }
    return null;
  }
}
