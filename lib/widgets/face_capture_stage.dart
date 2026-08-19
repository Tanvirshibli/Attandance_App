import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';

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
  const margin = 28.0;
  const coachingReserve = 56.0;
  final width = min(size.width * 0.62, max(0.0, size.width - margin * 2));
  final height = min(
    size.height * 0.58,
    max(0.0, size.height - coachingReserve - margin),
  );
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height / 2),
    width: width,
    height: height,
  );
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
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (cameraReady &&
                cameraController != null &&
                cameraController!.value.isInitialized)
              SizedBox(
                width: double.infinity,
                height: height,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: cameraController!.value.previewSize?.height ?? 480,
                    height: cameraController!.value.previewSize?.width ?? 640,
                    child: CameraPreview(cameraController!),
                  ),
                ),
              )
            else
              ColoredBox(
                color: Colors.white.withValues(alpha: 0.05),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white38),
                ),
              ),
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
              tickScale == null
                  ? _successTick()
                  : ScaleTransition(
                      scale: tickScale!,
                      child: _successTick(),
                    ),
            if (flash != null) Positioned.fill(child: flash!),
            if (topBadge != null)
              Positioned(
                top: 12,
                child: topBadge!,
              ),
            if (coachingMessage != null && coachingMessage!.isNotEmpty)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
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
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _successTick() {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.88),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
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
