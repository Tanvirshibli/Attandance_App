import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A face placement oval guide overlay that helps users position their face
/// at the correct distance and angle for accurate face recognition.
class FaceOvalGuide extends StatelessWidget {
  final double width;
  final double height;
  final Color guideColor;
  final String? instruction;
  final bool isProcessing;
  final bool isSuccess;
  final Widget? child;

  const FaceOvalGuide({
    super.key,
    this.width = 280,
    this.height = 360,
    this.guideColor = Colors.white,
    this.instruction,
    this.isProcessing = false,
    this.isSuccess = false,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height + 40, // extra space for instruction text
      child: Column(
        children: [
          SizedBox(
            width: width,
            height: height,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // The oval cutout overlay
                CustomPaint(
                  size: Size(width, height),
                  painter: _FaceOvalPainter(
                    guideColor: isSuccess
                        ? Colors.greenAccent
                        : isProcessing
                            ? Colors.orangeAccent
                            : guideColor,
                    isProcessing: isProcessing,
                  ),
                ),
                // Child widget (e.g., camera preview or image)
                ?child,
                // Corner marks for better visual guidance
                ..._buildCornerMarks(),
                // Center crosshair for eye alignment
                if (!isSuccess && !isProcessing)
                  Positioned(
                    top: height * 0.32,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _eyeGuide(),
                        SizedBox(width: width * 0.22),
                        _eyeGuide(),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (instruction != null) ...[
            const SizedBox(height: 10),
            Text(
              instruction!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: isSuccess
                    ? Colors.greenAccent
                    : isProcessing
                        ? Colors.orangeAccent
                        : Colors.white60,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _eyeGuide() {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
    );
  }

  List<Widget> _buildCornerMarks() {
    final color = isSuccess
        ? Colors.greenAccent
        : isProcessing
            ? Colors.orangeAccent
            : guideColor.withValues(alpha: 0.6);
    const len = 20.0;
    const t = 2.5;
    final ovalW = width * 0.65;
    final ovalH = height * 0.72;
    final left = (width - ovalW) / 2;
    final top = (height - ovalH) / 2;

    return [
      // Top left
      Positioned(
        left: left - 4,
        top: top - 4,
        child: SizedBox(
          width: len,
          height: len,
          child: CustomPaint(painter: _CornerMarkPainter(color, t, 0)),
        ),
      ),
      // Top right
      Positioned(
        right: left - 4,
        top: top - 4,
        child: SizedBox(
          width: len,
          height: len,
          child: CustomPaint(painter: _CornerMarkPainter(color, t, 1)),
        ),
      ),
      // Bottom left
      Positioned(
        left: left - 4,
        bottom: top - 4,
        child: SizedBox(
          width: len,
          height: len,
          child: CustomPaint(painter: _CornerMarkPainter(color, t, 2)),
        ),
      ),
      // Bottom right
      Positioned(
        right: left - 4,
        bottom: top - 4,
        child: SizedBox(
          width: len,
          height: len,
          child: CustomPaint(painter: _CornerMarkPainter(color, t, 3)),
        ),
      ),
    ];
  }
}

/// Animated version of the face oval guide with pulsing border
class AnimatedFaceOvalGuide extends StatefulWidget {
  final double width;
  final double height;
  final Color guideColor;
  final String? instruction;
  final bool isProcessing;
  final bool isSuccess;
  final Widget? child;

  const AnimatedFaceOvalGuide({
    super.key,
    this.width = 280,
    this.height = 360,
    this.guideColor = Colors.white,
    this.instruction,
    this.isProcessing = false,
    this.isSuccess = false,
    this.child,
  });

  @override
  State<AnimatedFaceOvalGuide> createState() => _AnimatedFaceOvalGuideState();
}

class _AnimatedFaceOvalGuideState extends State<AnimatedFaceOvalGuide>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final pulseOpacity = 0.3 + 0.4 * _controller.value;
        return FaceOvalGuide(
          width: widget.width,
          height: widget.height,
          guideColor: widget.guideColor.withValues(alpha: widget.isProcessing
              ? pulseOpacity
              : widget.isSuccess
                  ? 0.8
                  : 0.5),
          instruction: widget.instruction,
          isProcessing: widget.isProcessing,
          isSuccess: widget.isSuccess,
          child: widget.child,
        );
      },
    );
  }
}

/// Paints a face-shaped oval outline with a semi-transparent background
class _FaceOvalPainter extends CustomPainter {
  final Color guideColor;
  final bool isProcessing;

  _FaceOvalPainter({
    required this.guideColor,
    required this.isProcessing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.65,
      height: size.height * 0.72,
    );

    // Draw semi-transparent background outside the oval
    final bgPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    final bgPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(bgPath, bgPaint);

    // Draw the oval border
    final borderPaint = Paint()
      ..color = guideColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = isProcessing ? 3.0 : 2.0;

    canvas.drawOval(ovalRect, borderPaint);

    // Draw dashed center line (horizontal) for face alignment
    if (!isProcessing) {
      final dashPaint = Paint()
        ..color = guideColor.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;

      // Horizontal center line
      canvas.drawLine(
        Offset(ovalRect.left + 20, size.height / 2),
        Offset(ovalRect.right - 20, size.height / 2),
        dashPaint,
      );

      // Vertical center line
      canvas.drawLine(
        Offset(size.width / 2, ovalRect.top + 20),
        Offset(size.width / 2, ovalRect.bottom - 20),
        dashPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FaceOvalPainter oldDelegate) {
    return oldDelegate.guideColor != guideColor ||
        oldDelegate.isProcessing != isProcessing;
  }
}

class _CornerMarkPainter extends CustomPainter {
  final Color color;
  final double thickness;
  final int corner;

  _CornerMarkPainter(this.color, this.thickness, this.corner);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    switch (corner) {
      case 0:
        path.moveTo(0, size.height);
        path.lineTo(0, 0);
        path.lineTo(size.width, 0);
        break;
      case 1:
        path.moveTo(0, 0);
        path.lineTo(size.width, 0);
        path.lineTo(size.width, size.height);
        break;
      case 2:
        path.moveTo(0, 0);
        path.lineTo(0, size.height);
        path.lineTo(size.width, size.height);
        break;
      case 3:
        path.moveTo(size.width, 0);
        path.lineTo(size.width, size.height);
        path.lineTo(0, size.height);
        break;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
