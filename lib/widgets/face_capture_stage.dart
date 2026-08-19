import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';

const double faceGuideTopReserve = 88.0;
const double faceGuideMargin = 28.0;
const double faceGuideTickSize = 72.0;

Radius faceGuideCornerRadius(Rect rect) {
  return Radius.circular(rect.shortestSide * 0.22);
}

RRect faceGuideRRect(Rect rect) {
  return RRect.fromRectAndRadius(rect, faceGuideCornerRadius(rect));
}

Path buildFaceGuidePath(Rect rect) {
  return Path()..addRRect(faceGuideRRect(rect));
}

Rect faceGuideRect(Size size) {
  final width = min(size.width * 0.62, max(0.0, size.width - faceGuideMargin * 2));
  final height = min(
    size.height * 0.72,
    max(0.0, size.height - faceGuideTopReserve - faceGuideMargin),
  );
  return Rect.fromCenter(
    center: Offset(size.width / 2, faceGuideTopReserve + height / 2),
    width: width,
    height: height,
  );
}

Offset faceGuideTickOrigin(Size size, {double tickSize = faceGuideTickSize}) {
  final center = faceGuideRect(size).center;
  return Offset(center.dx - tickSize / 2, center.dy - tickSize / 2);
}

/// Full-preview face capture stage with dimmed rounded frame, corners, and coaching.
class FaceCaptureStage extends StatelessWidget {
  const FaceCaptureStage({
    super.key,
    required this.height,
    required this.cameraReady,
    required this.progress,
    required this.guideColor,
    this.cameraController,
    this.isMatching = false,
    this.showSuccessTick = false,
    this.tickScale,
    this.coachingMessage,
    this.coachingIcon,
    this.topBadge,
    this.flash,
    this.borderRadius = 24,
  });

  final double height;
  final bool cameraReady;
  final CameraController? cameraController;
  final double progress;
  final Color guideColor;
  final bool isMatching;
  final bool showSuccessTick;
  final Animation<double>? tickScale;
  final String? coachingMessage;
  final IconData? coachingIcon;
  final Widget? topBadge;
  final Widget? flash;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final guide = faceGuideRect(size);
            final tickOrigin = faceGuideTickOrigin(size);
            final hasCoaching =
                coachingMessage != null && coachingMessage!.isNotEmpty;
            final hasLabels = topBadge != null || hasCoaching;
            final labelBandHeight = max(0.0, guide.top - 8);

            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(child: _cameraPreview()),
                Positioned.fill(
                  child: CustomPaint(
                    painter: FaceGuidePainter(
                      guideColor: guideColor,
                      isMatching: isMatching,
                      progress: progress,
                      progressColor: progress >= 1.0
                          ? AppColors.success
                          : AppColors.primary,
                    ),
                  ),
                ),
                if (showSuccessTick)
                  Positioned(
                    left: tickOrigin.dx,
                    top: tickOrigin.dy,
                    width: faceGuideTickSize,
                    height: faceGuideTickSize,
                    child: tickScale == null
                        ? _successTick()
                        : ScaleTransition(
                            alignment: Alignment.center,
                            scale: tickScale!,
                            child: _successTick(),
                          ),
                  ),
                if (flash != null) Positioned.fill(child: flash!),
                if (hasLabels)
                  Positioned(
                    left: 16,
                    right: 16,
                    top: 8,
                    height: labelBandHeight,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (topBadge != null) topBadge!,
                          if (topBadge != null && hasCoaching)
                            const SizedBox(height: 6),
                          if (hasCoaching) _coachingChip(),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _cameraPreview() {
    if (cameraReady &&
        cameraController != null &&
        cameraController!.value.isInitialized) {
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: cameraController!.value.previewSize?.height ?? 480,
          height: cameraController!.value.previewSize?.width ?? 640,
          child: CameraPreview(cameraController!),
        ),
      );
    }
    return ColoredBox(
      color: Colors.white.withValues(alpha: 0.05),
      child: const Center(
        child: CircularProgressIndicator(color: Colors.white38),
      ),
    );
  }

  Widget _successTick() {
    return Container(
      width: faceGuideTickSize,
      height: faceGuideTickSize,
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.88),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
    );
  }

  Widget _coachingChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            coachingIcon ?? Icons.center_focus_strong_rounded,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              coachingMessage!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FaceGuidePainter extends CustomPainter {
  FaceGuidePainter({
    required this.guideColor,
    required this.isMatching,
    required this.progress,
    required this.progressColor,
  });

  final Color guideColor;
  final bool isMatching;
  final double progress;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    final faceRect = faceGuideRect(size);
    if (faceRect.width <= 0 || faceRect.height <= 0) return;

    final rrect = faceGuideRRect(faceRect);
    final facePath = buildFaceGuidePath(faceRect);

    final bgPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.48)
      ..style = PaintingStyle.fill;

    final bgPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addPath(facePath, Offset.zero)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(bgPath, bgPaint);

    final borderPaint = Paint()
      ..color = guideColor.withValues(alpha: 0.88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isMatching ? 2.4 : 1.6
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(rrect, borderPaint);

    final cornerPaint = Paint()
      ..color = guideColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = isMatching ? 4.2 : 3.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    _drawRoundedCorners(canvas, rrect, cornerPaint, 22);

    if (progress > 0) {
      final metrics = facePath.computeMetrics();
      if (metrics.isEmpty) return;
      final metric = metrics.first;
      final progressPath = metric.extractPath(
        0,
        metric.length * progress.clamp(0.0, 1.0),
      );
      canvas.drawPath(
        progressPath,
        Paint()
          ..color = progressColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = isMatching ? 3.2 : 2.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  void _drawRoundedCorners(
    Canvas canvas,
    RRect rrect,
    Paint paint,
    double arm,
  ) {
    final r = rrect.tlRadiusX;
    canvas.drawLine(
      Offset(rrect.left + r, rrect.top),
      Offset(rrect.left + r + arm, rrect.top),
      paint,
    );
    canvas.drawLine(
      Offset(rrect.left, rrect.top + r),
      Offset(rrect.left, rrect.top + r + arm),
      paint,
    );
    canvas.drawLine(
      Offset(rrect.right - r, rrect.top),
      Offset(rrect.right - r - arm, rrect.top),
      paint,
    );
    canvas.drawLine(
      Offset(rrect.right, rrect.top + r),
      Offset(rrect.right, rrect.top + r + arm),
      paint,
    );
    canvas.drawLine(
      Offset(rrect.left + r, rrect.bottom),
      Offset(rrect.left + r + arm, rrect.bottom),
      paint,
    );
    canvas.drawLine(
      Offset(rrect.left, rrect.bottom - r),
      Offset(rrect.left, rrect.bottom - r - arm),
      paint,
    );
    canvas.drawLine(
      Offset(rrect.right - r, rrect.bottom),
      Offset(rrect.right - r - arm, rrect.bottom),
      paint,
    );
    canvas.drawLine(
      Offset(rrect.right, rrect.bottom - r),
      Offset(rrect.right, rrect.bottom - r - arm),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant FaceGuidePainter oldDelegate) {
    return oldDelegate.guideColor != guideColor ||
        oldDelegate.isMatching != isMatching ||
        oldDelegate.progress != progress ||
        oldDelegate.progressColor != progressColor;
  }
}
