import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/theme.dart';
import '../services/face_recognition_service.dart';
import '../services/face_registration_api_service.dart';

/// 5-angle face registration screen with live camera preview.
/// Automatically detects each target angle and captures when held.
class FaceRegistrationScreen extends StatefulWidget {
  const FaceRegistrationScreen({super.key});

  @override
  State<FaceRegistrationScreen> createState() =>
      _FaceRegistrationScreenState();
}

class _FaceRegistrationScreenState extends State<FaceRegistrationScreen>
    with TickerProviderStateMixin {
  // ---- Services & Controllers ----
  final _faceService = FaceRecognitionService();
  final _faceRegistrationApiService = FaceRegistrationApiService();
  CameraController? _cameraController;

  // ---- State flags ----
  bool _cameraReady = false;
  bool _isCompleted = false;
  bool _isCapturing = false;
  String _statusMessage = 'Initializing camera...';
  bool _facePlacedCorrectly = false;

  // ---- Registration progress ----
  int _currentCapture = 0; // 0-based index into registrationAngles
  int _angleHoldFrames = 0;
  static const int _requiredHoldFrames = 2; // higher clarity before capture
  double _progress = 0.0;
  double _animatedProgress = 0.0;
  double _progressAnimationStart = 0.0;

  final List<bool> _captureResults =
      List.filled(FaceRecognitionService.registrationCaptures, false);

  // ---- Frame analysis ----
  Timer? _frameTimer;
  bool _processingFrame = false;

  // ---- Live face info ----
  bool _faceDetected = false;

  // ---- Animation ----
  late AnimationController _captureFlashAnim;
  late AnimationController _progressAnim;
  late AnimationController _tickAnim;
  late Animation<double> _tickScale;

  FaceAngle get _targetAngle {
    if (_currentCapture >= FaceRecognitionService.registrationCaptures) {
      return FaceAngle.straight;
    }
    return FaceRecognitionService.registrationAngles[_currentCapture];
  }

  // ================================================================
  // Lifecycle
  // ================================================================

  @override
  void initState() {
    super.initState();
    _captureFlashAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _progressAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _tickAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _tickScale = CurvedAnimation(parent: _tickAnim, curve: Curves.elasticOut);
    _progressAnim.addListener(() {
      if (!mounted) return;
      setState(() {
        _animatedProgress = lerpDouble(
              _progressAnimationStart,
              _progress,
              _progressAnim.value,
            ) ??
            _progress;
      });
    });
    _init();
  }

  Future<void> _init() async {
    await _faceService.initialize();
    await _faceService.deleteRegisteredFace();
    await _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (!mounted) return;
        setState(() => _statusMessage = 'Camera permission denied');
        return;
      }

      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (!mounted) return;
      setState(() {
        _cameraReady = true;
        _statusMessage =
            FaceRecognitionService.angleInstruction(_targetAngle);
      });

      _startFrameAnalysis();
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Camera error: $e');
    }
  }

  void _startFrameAnalysis() {
    _frameTimer?.cancel();
    _frameTimer =
        Timer.periodic(const Duration(milliseconds: 700), (_) => _analyzeFrame());
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    _cameraController?.dispose();
    _captureFlashAnim.dispose();
    _progressAnim.dispose();
    _tickAnim.dispose();
    super.dispose();
  }

  // ================================================================
  // Frame analysis
  // ================================================================

  Future<void> _analyzeFrame() async {
    if (_processingFrame ||
        _isCapturing ||
        _isCompleted ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }

    _processingFrame = true;
    File? tempFile;

    try {
      final xFile = await _cameraController!.takePicture();
      tempFile = File(xFile.path);
      final faces = await _faceService.detectFaces(tempFile);

      if (!mounted) return;

      if (faces.isEmpty) {
        setState(() {
          _faceDetected = false;
          _facePlacedCorrectly = false;
          _angleHoldFrames = 0;
          _statusMessage = 'Position your face in the frame';
        });
      } else if (faces.length > 1) {
        setState(() {
          _faceDetected = false;
          _facePlacedCorrectly = false;
          _angleHoldFrames = 0;
          _statusMessage = 'Only one face should be visible';
        });
      } else {
        final face = faces.first;
        final placementIssue = _facePlacementIssue(face);
        if (placementIssue != null) {
          setState(() {
            _faceDetected = true;
            _facePlacedCorrectly = false;
            _angleHoldFrames = 0;
            _statusMessage = placementIssue;
          });
          return;
        }

        final qualityIssue = _liveQualityIssue(face);
        if (qualityIssue != null) {
          setState(() {
            _faceDetected = true;
            _facePlacedCorrectly = true;
            _angleHoldFrames = 0;
            _statusMessage = qualityIssue;
          });
          return;
        }

        setState(() {
          _faceDetected = true;
          _facePlacedCorrectly = true;
        });

        if (_faceService.isTargetAngle(face, _targetAngle)) {
          _angleHoldFrames++;
          if (_angleHoldFrames >= _requiredHoldFrames) {
            setState(() => _statusMessage = 'Capturing...');
            await _captureRegistration(tempFile);
            tempFile = null; // prevent deletion — used for capture
          } else {
            setState(() => _statusMessage = 'Hold steady...');
          }
        } else {
          _angleHoldFrames = 0;
          setState(() {
            if (_targetAngle == FaceAngle.down) {
              _statusMessage =
                  'Lower your chin slightly and keep eyes visible';
            } else {
              _statusMessage =
                  FaceRecognitionService.angleInstruction(_targetAngle);
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Frame analysis error: $e');
    } finally {
      try {
        await tempFile?.delete();
      } catch (_) {}
      _processingFrame = false;
    }
  }

  String? _facePlacementIssue(Face face) {
      final dimensions = _resolvePreviewDimensions();
      if (dimensions == null) return null;

      final primary = _faceService.checkFrontCamera(
        face,
        dimensions.width,
        dimensions.height,
        requireCentering: true,
        centerTolerance: 0.28,
      );
      if (primary.isFrontCamera) return null;

      FrontCameraCheckResult? swapped;
      if (dimensions.width != dimensions.height) {
        swapped = _faceService.checkFrontCamera(
          face,
          dimensions.height,
          dimensions.width,
          requireCentering: true,
          centerTolerance: 0.28,
        );
        if (swapped.isFrontCamera) return null;
      }

      final issue = swapped?.issue ?? primary.issue;
      if (issue != null && issue.contains('small')) {
        return 'Move closer and place your face inside the guide';
      }

      return 'Place your face correctly inside the face guide';
  }

  String? _liveQualityIssue(Face face) {
      final dimensions = _resolvePreviewDimensions();
      if (dimensions == null) return null;

      final primary = _faceService.checkFaceQuality(
        face,
        dimensions.width,
        dimensions.height,
        skipRotationCheck: _targetAngle != FaceAngle.straight,
      );
      if (primary.isAcceptable) return null;

      FaceQualityResult? swapped;
      if (dimensions.width != dimensions.height) {
        swapped = _faceService.checkFaceQuality(
          face,
          dimensions.height,
          dimensions.width,
          skipRotationCheck: _targetAngle != FaceAngle.straight,
        );
        if (swapped.isAcceptable) return null;
      }

      final quality =
          swapped != null && swapped.score > primary.score ? swapped : primary;
      if (quality.issues.isEmpty) {
        return 'Hold still and keep your face clear in the guide';
      }
      return quality.issues.first;
  }

    ({int width, int height})? _resolvePreviewDimensions() {
      final previewSize = _cameraController?.value.previewSize;
      if (previewSize == null) return null;

      final width = previewSize.width.toInt();
      final height = previewSize.height.toInt();
      if (width <= 0 || height <= 0) return null;

      return (width: width, height: height);
    }

  // ================================================================
  // Capture & registration
  // ================================================================

  Future<void> _captureRegistration(File imageFile) async {
    _isCapturing = true;
    _captureFlashAnim.forward().then((_) => _captureFlashAnim.reverse());

    try {
      final result = await _faceService.registerFaceCapture(
        imageFile,
        captureNumber: _currentCapture + 1,
        targetAngle: _targetAngle,
      );

      if (!mounted) return;

      if (result.success) {
        setState(() => _captureResults[_currentCapture] = true);

        if (result.isPartial) {
          // More captures needed
          setState(() {
            _currentCapture++;
            _progress =
                _currentCapture / FaceRecognitionService.registrationCaptures;
            _angleHoldFrames = 0;
            _statusMessage =
                FaceRecognitionService.angleInstruction(_targetAngle);
          });
          _progressAnimationStart = _animatedProgress;
          _progressAnim.forward(from: 0);
        } else {
          // All captures done
          var savedToBackend = false;
          final registrationData = _faceService.exportRegistrationData();
          if (registrationData != null) {
            savedToBackend = await _faceRegistrationApiService
                .saveFaceRegistration(registrationData);
          }

          _frameTimer?.cancel();
          setState(() {
            _isCompleted = true;
            _progress = 1.0;
            _statusMessage = savedToBackend
                ? 'Registration complete!'
                : 'Face saved locally for this session, but backend sync failed.';
          });
          _progressAnimationStart = _animatedProgress;
          _progressAnim.forward(from: 0);
          _tickAnim.forward(from: 0);
        }
      } else {
        setState(() {
          _angleHoldFrames = 0;
          _statusMessage = result.isDifferentPerson
              ? 'Different person detected! Try again.'
              : result.message;
        });
        if (result.isDifferentPerson) _showDifferentPersonDialog();
      }
    } catch (e) {
      setState(() {
        _angleHoldFrames = 0;
        _statusMessage = 'Capture failed. Try again.';
      });
    } finally {
      _isCapturing = false;
      try {
        await imageFile.delete();
      } catch (_) {}
    }
  }

  void _showDifferentPersonDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F36),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.error, size: 26),
            const SizedBox(width: 10),
            Text('Different Person!',
                style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
          ],
        ),
        content: Text(
          'The captured face doesn\'t match the previous captures. '
          'All registration photos must be of the same person.',
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK, I\'ll retry',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600, color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // Build
  // ================================================================

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final previewHeight = screenWidth * 1.1;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Face Registration',
            style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Step dots
          _buildStepIndicator(),

          // Camera preview
          _buildCameraPreview(previewHeight),

          // Scrollable info
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                children: [
                  _buildAngleProgressCard(),
                  const SizedBox(height: 12),
                  _buildTipsCard(),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),

          // Done button
          if (_isCompleted) _buildDoneButton(),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  // Step indicator (horizontal dots)
  // ----------------------------------------------------------------
  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          FaceRecognitionService.registrationCaptures,
          (i) {
            final isDone = _captureResults[i];
            final isCurrent = i == _currentCapture && !_isCompleted;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: isCurrent ? 28 : 12,
              height: 12,
              decoration: BoxDecoration(
                color: isDone
                    ? AppColors.success
                    : isCurrent
                        ? AppColors.primary
                        : Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: isDone
                  ? const Center(
                      child:
                          Icon(Icons.check, size: 9, color: Colors.white))
                  : null,
            );
          },
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  // Camera preview with overlay
  // ----------------------------------------------------------------
  Widget _buildCameraPreview(double height) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Camera feed
          if (_cameraReady && _cameraController != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                width: double.infinity,
                height: height,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _cameraController!.value.previewSize?.height ??
                        480,
                    height:
                        _cameraController!.value.previewSize?.width ?? 640,
                    child: CameraPreview(_cameraController!),
                  ),
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              height: height,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Center(
                  child:
                      CircularProgressIndicator(color: Colors.white38)),
            ),

          Positioned.fill(
            child: AnimatedBuilder(
              animation: _progressAnim,
              builder: (context, child) => CustomPaint(
                painter: _FaceRegistrationProgressPainter(
                  progress: _animatedProgress,
                  trackColor: Colors.white.withValues(alpha: 0.15),
                  progressColor: _progress >= 1.0
                      ? AppColors.success
                      : AppColors.primary,
                ),
              ),
            ),
          ),

          // Face-shaped oval overlay
          Positioned.fill(
            child: CustomPaint(
              painter: _FaceOvalOverlayPainter(
                guideColor: _faceDetected
                    ? (_facePlacedCorrectly && _angleHoldFrames > 0
                        ? AppColors.success
                        : _facePlacedCorrectly
                            ? AppColors.primary
                            : AppColors.warning)
                    : Colors.white54,
                isMatching: _angleHoldFrames > 0,
              ),
            ),
          ),

          if (_progress >= 1.0)
            ScaleTransition(
              scale: _tickScale,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.88),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded,
                    color: Colors.white, size: 40),
              ),
            ),

          // Capture-flash white overlay
          FadeTransition(
            opacity: _captureFlashAnim,
            child: Container(
              width: double.infinity,
              height: height,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),

          // Step label (top)
          Positioned(
            top: 12,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _isCompleted
                    ? 'Done!'
                    : 'Step ${_currentCapture + 1} of ${FaceRecognitionService.registrationCaptures}',
                style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
            ),
          ),

          // Instruction (bottom)
          Positioned(
            bottom: 20,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _angleIcon(_targetAngle),
                  const SizedBox(width: 8),
                  Text(
                    _statusMessage,
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                  ),
                ],
              ),
            ),
          ),

          // Completed overlay
          if (_isCompleted)
            Container(
              width: double.infinity,
              height: height,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded,
                        color: Colors.white, size: 48),
                  ),
                  const SizedBox(height: 16),
                  Text('Registration Complete!',
                      style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  Text(
                      '${FaceRecognitionService.registrationCaptures} angles captured',
                      style: GoogleFonts.poppins(
                          fontSize: 14, color: Colors.white60)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _angleIcon(FaceAngle angle) {
    IconData icon;
    switch (angle) {
      case FaceAngle.straight:
        icon = Icons.face;
        break;
      case FaceAngle.left:
        icon = Icons.turn_left;
        break;
      case FaceAngle.right:
        icon = Icons.turn_right;
        break;
      case FaceAngle.up:
        icon = Icons.arrow_upward;
        break;
      case FaceAngle.down:
        icon = Icons.arrow_downward;
        break;
      case FaceAngle.unknown:
        icon = Icons.help_outline;
        break;
    }
    return Icon(icon, color: Colors.white, size: 20);
  }

  // ----------------------------------------------------------------
  // Progress list
  // ----------------------------------------------------------------
  Widget _buildAngleProgressCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Registration Progress',
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
          const SizedBox(height: 12),
          ...List.generate(FaceRecognitionService.registrationCaptures,
              (i) {
            final angle = FaceRecognitionService.registrationAngles[i];
            final done = _captureResults[i];
            final isCurrent = i == _currentCapture && !_isCompleted;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  _angleIcon(angle),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      FaceRecognitionService.angleDisplayName(angle),
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: done
                            ? AppColors.success
                            : isCurrent
                                ? Colors.white
                                : Colors.white38,
                        fontWeight:
                            isCurrent ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (done)
                    const Icon(Icons.check_circle,
                        color: AppColors.success, size: 20)
                  else if (isCurrent)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  // Tips
  // ----------------------------------------------------------------
  Widget _buildTipsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_outline,
                  color: AppColors.info, size: 18),
              const SizedBox(width: 8),
              Text('Tips',
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.info)),
            ],
          ),
          const SizedBox(height: 10),
          ...[
            'Ensure good, even lighting on your face',
            'Follow the angle instructions carefully',
            'Hold each position steady for about 1 second',
            'Keep both eyes open during captures',
            'Only your face should be visible in the frame',
          ].map((tip) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ',
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: Colors.white54)),
                    Expanded(
                      child: Text(tip,
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: Colors.white54)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  // Done button
  // ----------------------------------------------------------------
  Widget _buildDoneButton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: Text('Done ✓',
                style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}

// ================================================================
// Oval overlay painter
// ================================================================

Path _buildRegistrationFacePath(Rect rect) {
  final cx = rect.center.dx;
  final top = rect.top;
  final bottom = rect.bottom;
  final left = rect.left;
  final right = rect.right;
  final cheekY = rect.top + rect.height * 0.38;
  final jawY = rect.top + rect.height * 0.78;

  return Path()
    ..moveTo(cx, top)
    ..cubicTo(
      cx + rect.width * 0.34,
      top + rect.height * 0.02,
      right,
      cheekY,
      cx + rect.width * 0.24,
      jawY,
    )
    ..cubicTo(
      cx + rect.width * 0.16,
      bottom,
      cx - rect.width * 0.16,
      bottom,
      cx - rect.width * 0.24,
      jawY,
    )
    ..cubicTo(
      left,
      cheekY,
      cx - rect.width * 0.34,
      top + rect.height * 0.02,
      cx,
      top,
    )
    ..close();
}

class _FaceRegistrationProgressPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color progressColor;
  static const double _strokeWidth = 5;

  _FaceRegistrationProgressPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final faceRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.45),
      width: size.width * 0.62,
      height: size.height * 0.72,
    ).deflate(_strokeWidth / 2);

    final facePath = _buildRegistrationFacePath(faceRect);

    canvas.drawPath(
      facePath,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..strokeJoin = StrokeJoin.round,
    );

    if (progress > 0) {
      final metric = facePath.computeMetrics().first;
      final progressPath = metric.extractPath(
        0,
        metric.length * progress.clamp(0.0, 1.0),
      );

      canvas.drawPath(
        progressPath,
        Paint()
          ..color = progressColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = _strokeWidth + 1
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FaceRegistrationProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.progressColor != progressColor;
  }
}

class _FaceOvalOverlayPainter extends CustomPainter {
  final Color guideColor;
  final bool isMatching;

  _FaceOvalOverlayPainter({
    required this.guideColor,
    required this.isMatching,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final faceRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.45),
      width: size.width * 0.62,
      height: size.height * 0.72,
    );
    final facePath = _buildRegistrationFacePath(faceRect);

    // Semi-transparent background outside the face guide
    final bgPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;

    final bgPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addPath(facePath, Offset.zero)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(bgPath, bgPaint);

    // Face-shaped border
    final borderPaint = Paint()
      ..color = guideColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = isMatching ? 3.5 : 2.0
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(facePath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _FaceOvalOverlayPainter old) =>
      old.guideColor != guideColor || old.isMatching != isMatching;
}
