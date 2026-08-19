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
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height * 0.45),
    width: size.width * 0.62,
    height: size.height * 0.72,
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
                painter: FaceGuideProgressPainter(
                  progress: progress,
                  trackColor: Colors.white.withValues(alpha: 0.15),
                  progressColor: progress >= 1.0
                      ? AppColors.success
                      : AppColors.primary,
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: FaceGuideOverlayPainter(
                  guideColor: guideColor,
                  isMatching: isMatching,
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

class FaceGuideOverlayPainter extends CustomPainter {
  FaceGuideOverlayPainter({
    required this.guideColor,
    required this.isMatching,
  });

  final Color guideColor;
  final bool isMatching;

  @override
  void paint(Canvas canvas, Size size) {
    final faceRect = faceGuideRect(size);
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
    canvas.drawRRect(faceGuideRRect(faceRect), borderPaint);

    final cornerPaint = Paint()
      ..color = guideColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = isMatching ? 4.2 : 3.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    const arm = 22.0;
    _drawCorner(canvas, faceRect.topLeft, Offset(arm, 0), Offset(0, arm), cornerPaint);
    _drawCorner(canvas, faceRect.topRight, Offset(-arm, 0), Offset(0, arm), cornerPaint);
    _drawCorner(canvas, faceRect.bottomLeft, Offset(arm, 0), Offset(0, -arm), cornerPaint);
    _drawCorner(canvas, faceRect.bottomRight, Offset(-arm, 0), Offset(0, -arm), cornerPaint);
  }

  void _drawCorner(
    Canvas canvas,
    Offset origin,
    Offset horizontal,
    Offset vertical,
    Paint paint,
  ) {
    canvas.drawLine(origin, origin + horizontal, paint);
    canvas.drawLine(origin, origin + vertical, paint);
  }

  @override
  bool shouldRepaint(covariant FaceGuideOverlayPainter oldDelegate) {
    return oldDelegate.guideColor != guideColor ||
        oldDelegate.isMatching != isMatching;
  }
}

class FaceGuideProgressPainter extends CustomPainter {
  FaceGuideProgressPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    this.strokeWidth = 5,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final faceRect = faceGuideRect(size).deflate(strokeWidth / 2);
    final facePath = buildFaceGuidePath(faceRect);

    canvas.drawRRect(
      faceGuideRRect(faceRect),
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round,
    );

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
          ..strokeWidth = strokeWidth + 1
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant FaceGuideProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.trackColor != trackColor;
  }
}
