import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

import '../config/theme.dart';
import '../services/face_recognition_service.dart';
import '../services/attendance_request_service.dart';

// ================================================================
// Face path helpers & progress painter
// ================================================================

Path _buildFaceGuidePath(Rect rect) {
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

class _FaceScanProgressPainter extends CustomPainter {
  final double progress; // 0.0 – 1.0
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;
  static const double _inset = 8.0;

  _FaceScanProgressPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    this.strokeWidth = 5.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final faceRect = Rect.fromLTWH(
      _inset,
      _inset,
      size.width - (_inset * 2),
      size.height - (_inset * 2),
    ).deflate(strokeWidth / 2);

    final facePath = _buildFaceGuidePath(faceRect);

    canvas.drawPath(
      facePath,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
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
          ..strokeWidth = strokeWidth + 1
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FaceScanProgressPainter old) =>
      old.progress != progress || old.progressColor != progressColor;
}

class _FaceShapeClipper extends CustomClipper<Path> {
  const _FaceShapeClipper();

  @override
  Path getClip(Size size) {
    return _buildFaceGuidePath(Rect.fromLTWH(0, 0, size.width, size.height));
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

// ================================================================
// Enums
// ================================================================

/// Phase of the check-in flow
enum CheckInPhase { initializing, scanning, verifying, gps, success, error }

/// Internal blink-detection phases
enum _BlinkPhase { waitingOpen, waitingClosed, waitingReopen, done }

// ================================================================
// CheckInScreen
// ================================================================

class CheckInScreen extends StatefulWidget {
  final VoidCallback onCheckIn;
  final bool isCheckOut;

  const CheckInScreen({
    super.key,
    required this.onCheckIn,
    this.isCheckOut = false,
  });

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen>
    with TickerProviderStateMixin {
  static const int _minChallengesBeforeEarlyVerify = 2;

  // ---- Services & Controllers ----
  final _faceService = FaceRecognitionService();
  final _attendanceRequestService = AttendanceRequestService();
  CameraController? _cameraController;

  // ---- State ----
  CheckInPhase _phase = CheckInPhase.initializing;
  String _statusMessage = 'Initializing...';
  String _errorMessage = '';
  bool _cameraReady = false;

  // ---- Challenge tracking ----
  late List<ChallengeType> _challenges;
  int _currentChallengeIndex = 0;
  late List<bool> _challengeResults;
  double _progress = 0.0;
  double _animatedProgress = 0.0;
  double _progressAnimationStart = 0.0;

  // Blink sub-state
  _BlinkPhase _blinkPhase = _BlinkPhase.waitingOpen;

  // Angle hold counter
  int _angleHoldFrames = 0;
  static const int _requiredHoldFrames = 2; // ~1.4 s at 700 ms interval

  // ---- Face data ----
  bool _faceDetected = false;
  bool _facePlacedCorrectly = false;
  bool _faceVerified = false;
  double _verificationConfidence = 0;

  // ---- GPS ----
  Position? _position;
  String _address = '';

  // ---- Frame analysis ----
  Timer? _frameTimer;
  bool _processingFrame = false;
  bool _isTakingPicture = false;

  // ---- Animations ----
  late AnimationController _progressAnim;
  late AnimationController _tickAnim;
  late Animation<double> _tickScale;

  // ================================================================
  // Lifecycle
  // ================================================================

  @override
  void initState() {
    super.initState();
    _progressAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _tickAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _tickScale =
        CurvedAnimation(parent: _tickAnim, curve: Curves.elasticOut);
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
    _setupChallenges();
    _init();
  }

  void _setupChallenges() {
    _challenges = List.of([
      ChallengeType.lookStraight,
      ChallengeType.smile,
      ChallengeType.blink,
      ChallengeType.turnLeft,
      ChallengeType.turnRight,
    ])..shuffle(Random());
    _challengeResults = List.filled(_challenges.length, false);
    _currentChallengeIndex = 0;
    _progress = 0;
    _animatedProgress = 0;
    _progressAnimationStart = 0;
    _blinkPhase = _BlinkPhase.waitingOpen;
    _angleHoldFrames = 0;
  }

  Future<void> _init() async {
    await _faceService.initialize();

    // Ensure face is registered
    final isRegistered = await _faceService.isFaceRegistered();
    if (!isRegistered) {
      if (!mounted) return;
      setState(() {
        _phase = CheckInPhase.error;
        _errorMessage =
            'No face registered. Please register your face in Profile first.';
      });
      return;
    }

    await _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (!mounted) return;
        setState(() {
          _phase = CheckInPhase.error;
          _errorMessage = 'Camera permission denied.';
        });
        return;
      }

      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      setState(() {
        _cameraReady = true;
        _phase = CheckInPhase.scanning;
        _statusMessage = FaceRecognitionService.challengeInstruction(
            _challenges[_currentChallengeIndex]);
      });

      _startFrameAnalysis();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = CheckInPhase.error;
        _errorMessage = 'Camera initialization failed: $e';
      });
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
    _progressAnim.dispose();
    _tickAnim.dispose();
    super.dispose();
  }

  // ================================================================
  // Frame analysis loop
  // ================================================================

  Future<void> _waitForCameraIdle({Duration timeout = const Duration(seconds: 2)}) async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (!_processingFrame &&
          !_isTakingPicture &&
          !controller.value.isTakingPicture) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 40));
    }
  }

  Future<XFile?> _takePictureSafely() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return null;
    if (_isTakingPicture || controller.value.isTakingPicture) return null;

    _isTakingPicture = true;
    try {
      return await controller.takePicture();
    } on CameraException catch (e) {
      debugPrint('Camera capture skipped: ${e.code} ${e.description}');
      return null;
    } finally {
      _isTakingPicture = false;
    }
  }

  Future<void> _analyzeFrame() async {
    if (_processingFrame ||
        _phase != CheckInPhase.scanning ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }

    _processingFrame = true;
    File? tempFile;

    try {
      final xFile = await _takePictureSafely();
      if (xFile == null) {
        return;
      }
      tempFile = File(xFile.path);
      final faces = await _faceService.detectFaces(tempFile);

      if (!mounted) return;

      if (faces.isEmpty) {
        setState(() {
          _faceDetected = false;
          _facePlacedCorrectly = false;
          _angleHoldFrames = 0;
          _statusMessage = 'Position your face in the guide';
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
        final frameDimensions = await _resolveFrameDimensions(tempFile);
        if (!_isFacePlacedCorrectly(face, frameDimensions)) {
          setState(() {
            _faceDetected = true;
            _facePlacedCorrectly = false;
            _angleHoldFrames = 0;
            _blinkPhase = _BlinkPhase.waitingOpen;
            _statusMessage =
                'Place your face correctly inside the face guide';
          });
        } else {
          setState(() {
            _faceDetected = true;
            _facePlacedCorrectly = true;
          });
          await _processChallenge(face);
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

  // ================================================================
  // Challenge evaluation
  // ================================================================

  Future<void> _processChallenge(Face face) async {
    if (_currentChallengeIndex >= _challenges.length) return;

    final challenge = _challenges[_currentChallengeIndex];
    bool passed = false;

    switch (challenge) {
      case ChallengeType.lookStraight:
        passed = _checkAngleChallenge(face, FaceAngle.straight,
            'Look straight at the camera');
        break;
      case ChallengeType.smile:
        passed = _faceService.isSmiling(face);
        if (!passed) setState(() => _statusMessage = 'Smile! 😄');
        break;
      case ChallengeType.blink:
        _handleBlinkChallenge(face);
        passed = _blinkPhase == _BlinkPhase.done;
        if (!passed) {
          final msg = switch (_blinkPhase) {
            _BlinkPhase.waitingOpen => 'Open your eyes and look at camera',
            _BlinkPhase.waitingClosed => 'Now blink your eyes',
            _BlinkPhase.waitingReopen => 'Open your eyes again',
            _BlinkPhase.done => 'Blink detected ✓',
          };
          setState(() => _statusMessage = msg);
        }
        break;
      case ChallengeType.turnLeft:
        passed = _checkAngleChallenge(
            face, FaceAngle.left, 'Turn your face slightly left');
        break;
      case ChallengeType.turnRight:
        passed = _checkAngleChallenge(
            face, FaceAngle.right, 'Turn your face slightly right');
        break;
    }

    if (passed) {
      await _completeChallenge();
    }
  }

  bool _isFacePlacedCorrectly(
    Face face,
    ({int width, int height})? frameDimensions,
  ) {
    if (frameDimensions == null) return true;

    final imageWidth = frameDimensions.width;
    final imageHeight = frameDimensions.height;

    final placement = _faceService.checkFrontCamera(
      face,
      imageWidth,
      imageHeight,
      requireCentering: true,
      centerTolerance: 0.35,
    );
    if (placement.isFrontCamera) return true;

    if (imageWidth != imageHeight) {
      final swappedPlacement = _faceService.checkFrontCamera(
        face,
        imageHeight,
        imageWidth,
        requireCentering: true,
        centerTolerance: 0.35,
      );
      if (swappedPlacement.isFrontCamera) return true;
    }

    return false;
  }

  Future<({int width, int height})?> _resolveFrameDimensions(File frameFile) async {
    try {
      final bytes = await frameFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded != null && decoded.width > 0 && decoded.height > 0) {
        return (width: decoded.width, height: decoded.height);
      }
    } catch (_) {}

    final previewSize = _cameraController?.value.previewSize;
    if (previewSize == null) return null;

    final width = previewSize.width.toInt();
    final height = previewSize.height.toInt();
    if (width <= 0 || height <= 0) return null;

    return (width: width, height: height);
  }

  /// Check an angle-based challenge with hold requirement.
  bool _checkAngleChallenge(
      Face face, FaceAngle target, String instruction) {
    if (_faceService.isTargetAngle(face, target)) {
      _angleHoldFrames++;
      if (_angleHoldFrames >= _requiredHoldFrames) return true;
      setState(() => _statusMessage = 'Hold steady...');
      return false;
    } else {
      _angleHoldFrames = 0;
      setState(() => _statusMessage = instruction);
      return false;
    }
  }

  void _handleBlinkChallenge(Face face) {
    switch (_blinkPhase) {
      case _BlinkPhase.waitingOpen:
        if (_faceService.areEyesOpen(face)) {
          _blinkPhase = _BlinkPhase.waitingClosed;
        }
        break;
      case _BlinkPhase.waitingClosed:
        if (_faceService.areEyesClosed(face)) {
          _blinkPhase = _BlinkPhase.waitingReopen;
        }
        break;
      case _BlinkPhase.waitingReopen:
        if (_faceService.areEyesOpen(face)) {
          _blinkPhase = _BlinkPhase.done;
        }
        break;
      case _BlinkPhase.done:
        break;
    }
  }

  Future<void> _completeChallenge() async {
    setState(() {
      _challengeResults[_currentChallengeIndex] = true;
      _currentChallengeIndex++;
      _progress = _currentChallengeIndex / _challenges.length;
      _angleHoldFrames = 0;
      _blinkPhase = _BlinkPhase.waitingOpen;
      _statusMessage = 'Checking identity...';
    });

    _progressAnimationStart = _animatedProgress;
    _progressAnim.forward(from: 0);

    if (_currentChallengeIndex >= _challenges.length) {
      // Show green tick and proceed to verification
      await _tickAnim.forward(from: 0);
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      await _verifyFace();
      return;
    }

    if (_currentChallengeIndex < _minChallengesBeforeEarlyVerify) {
      setState(() {
        _statusMessage = FaceRecognitionService.challengeInstruction(
          _challenges[_currentChallengeIndex],
        );
      });
      return;
    }

    final verifiedEarly = await _tryEarlyVerification();
    if (verifiedEarly || !mounted) return;

    setState(() {
      _statusMessage = FaceRecognitionService.challengeInstruction(
        _challenges[_currentChallengeIndex],
      );
    });
  }

  Future<bool> _tryEarlyVerification() async {
    _frameTimer?.cancel();
    await _waitForCameraIdle();

    if (!mounted ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return false;
    }

    setState(() {
      _phase = CheckInPhase.verifying;
      _statusMessage = 'Checking if additional steps are needed...';
    });

    try {
      final result = await _verifyFaceWithRetries(attempts: 2);
      if (result == null) {
        if (!mounted) return false;
        setState(() => _phase = CheckInPhase.scanning);
        _startFrameAnalysis();
        return false;
      }

      if (!mounted) return false;

      if (result.isMatch) {
        setState(() {
          _faceVerified = true;
          _verificationConfidence = result.confidence;
          for (var i = 0; i < _challengeResults.length; i++) {
            _challengeResults[i] = true;
          }
          _currentChallengeIndex = _challenges.length;
          _progress = 1.0;
          _statusMessage =
              'Identity verified early — additional challenge steps not required.';
        });

        _progressAnimationStart = _animatedProgress;
        _progressAnim.forward(from: 0);
        await _tickAnim.forward(from: 0);
        await _captureGPS();
        return true;
      }
    } catch (e) {
      debugPrint('Early verification fallback: $e');
    }

    if (!mounted) return false;

    setState(() {
      _phase = CheckInPhase.scanning;
      _statusMessage = FaceRecognitionService.challengeInstruction(
        _challenges[_currentChallengeIndex],
      );
    });
    _startFrameAnalysis();
    return false;
  }

  String _activeStatusMessage() {
    if (_phase == CheckInPhase.scanning && !_facePlacedCorrectly) {
      return 'Place your face correctly inside the face guide';
    }
    return _statusMessage;
  }

  // ================================================================
  // Face verification & GPS
  // ================================================================

  Future<void> _verifyFace() async {
    _frameTimer?.cancel();
    await _waitForCameraIdle();

    if (!mounted ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }

    setState(() {
      _phase = CheckInPhase.verifying;
      _statusMessage = 'Verifying identity...';
    });

    try {
      final result = await _verifyFaceWithRetries(attempts: 3);

      if (result == null) {
        setState(() {
          _phase = CheckInPhase.error;
          _errorMessage =
              'Verification failed: camera is busy. Please tap Retry.';
        });
        return;
      }

      if (!mounted) return;

      if (result.isMatch) {
        setState(() {
          _faceVerified = true;
          _verificationConfidence = result.confidence;
          _statusMessage = result.message;
        });
        await _captureGPS();
      } else {
        setState(() {
          _phase = CheckInPhase.error;
          _errorMessage = result.message;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = CheckInPhase.error;
        _errorMessage = 'Verification failed: $e';
      });
    }
  }

  Future<FaceVerificationResult?> _verifyFaceWithRetries({
    int attempts = 3,
  }) async {
    FaceVerificationResult? bestResult;

    for (var i = 0; i < attempts; i++) {
      final xFile = await _takePictureSafely();
      if (xFile == null) continue;

      final file = File(xFile.path);
      final result = await _faceService.verifyFace(file, requireSmile: false);
      try {
        await file.delete();
      } catch (_) {}

      if (bestResult == null || result.confidence > bestResult.confidence) {
        bestResult = result;
      }

      if (result.isMatch) {
        return result;
      }

      if (i < attempts - 1) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }

    return bestResult;
  }

  Future<void> _captureGPS() async {
    setState(() {
      _phase = CheckInPhase.gps;
      _statusMessage = 'Capturing location...';
    });

    try {
      final locPerm = await Permission.location.request();
      if (!locPerm.isGranted) {
        setState(() {
          _phase = CheckInPhase.error;
          _errorMessage = 'Location permission denied';
        });
        return;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _phase = CheckInPhase.error;
          _errorMessage = 'Location services are disabled';
        });
        return;
      }

      _position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      try {
        final placemarks = await placemarkFromCoordinates(
            _position!.latitude, _position!.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          _address =
              [p.street, p.subLocality, p.locality, p.country]
                  .where((s) => s != null && s.isNotEmpty)
                  .join(', ');
        }
      } catch (_) {
        _address =
            '${_position!.latitude.toStringAsFixed(4)}, '
            '${_position!.longitude.toStringAsFixed(4)}';
      }

      if (!mounted) return;

      final attendanceResult = await _attendanceRequestService.submitSelfPunch(
        isCheckOut: widget.isCheckOut,
        latitude: _position!.latitude,
        longitude: _position!.longitude,
        address: _address,
        faceRegistration: _faceService.exportRegistrationData(),
      );

      if (!attendanceResult.success) {
        setState(() {
          _phase = CheckInPhase.error;
          _errorMessage = attendanceResult.message ??
              'Attendance request submission failed.';
        });
        return;
      }

      setState(() {
        _phase = CheckInPhase.success;
        _statusMessage = widget.isCheckOut
            ? 'Check-out request submitted!'
            : 'Check-in request submitted!';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = CheckInPhase.error;
        _errorMessage = 'Location capture failed: $e';
      });
    }
  }

  // ================================================================
  // User actions
  // ================================================================

  void _handleDone() {
    widget.onCheckIn();
    Navigator.of(context).pop();
  }

  void _retry() {
    _frameTimer?.cancel();
    _tickAnim.reset();
    _setupChallenges();
    setState(() {
      _faceVerified = false;
      _facePlacedCorrectly = false;
      _errorMessage = '';
      _phase = CheckInPhase.scanning;
      _statusMessage = FaceRecognitionService.challengeInstruction(
          _challenges[_currentChallengeIndex]);
    });
    _startFrameAnalysis();
  }

  // ================================================================
  // Build
  // ================================================================

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final faceWidth = sw * 0.64;
    final faceHeight = faceWidth * 1.28;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.isCheckOut ? 'Check Out' : 'Check In',
            style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // ---- FIXED TOP: Camera + Circular Progress ----
          _buildCameraSection(faceWidth, faceHeight),

          // ---- SCROLLABLE MIDDLE ----
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                children: [
                  _buildChallengeList(),
                  if (_faceVerified) _buildVerificationCard(),
                  if (_phase == CheckInPhase.gps ||
                      _phase == CheckInPhase.success)
                    _buildGPSCard(),
                  if (_phase == CheckInPhase.error) _buildErrorCard(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // ---- FIXED BOTTOM: Action Button ----
          _buildBottomButton(),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  // Camera section with circular progress
  // ----------------------------------------------------------------
  Widget _buildCameraSection(double width, double height) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          SizedBox(
            width: width + 28,
            height: height + 28,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Camera preview clipped to face shape
                if (_cameraReady && _cameraController != null)
                  ClipPath(
                    clipper: const _FaceShapeClipper(),
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width:
                              _cameraController!.value.previewSize?.height ??
                                  width,
                          height:
                              _cameraController!.value.previewSize?.width ??
                                  height,
                          child: CameraPreview(_cameraController!),
                        ),
                      ),
                    ),
                  )
                else
                  ClipPath(
                    clipper: const _FaceShapeClipper(),
                    child: Container(
                      width: width,
                      height: height,
                      color: Colors.white.withValues(alpha: 0.05),
                      child: const Center(
                          child: CircularProgressIndicator(
                              color: Colors.white38)),
                    ),
                  ),

                // Clockwise progress around face path
                SizedBox(
                  width: width + 18,
                  height: height + 18,
                  child: AnimatedBuilder(
                    animation: _progressAnim,
                    builder: (context, child) => CustomPaint(
                      painter: _FaceScanProgressPainter(
                        progress: _animatedProgress,
                        trackColor:
                            Colors.white.withValues(alpha: 0.15),
                        progressColor: _progress >= 1.0
                            ? AppColors.success
                            : AppColors.primary,
                        strokeWidth: 5,
                      ),
                    ),
                  ),
                ),

                // Green tick when all challenges pass
                if (_progress >= 1.0)
                  ScaleTransition(
                    scale: _tickScale,
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.85),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: Colors.white, size: 40),
                    ),
                  ),

                // "No face" badge
                if (_cameraReady &&
                    (!_faceDetected || !_facePlacedCorrectly) &&
                    _phase == CheckInPhase.scanning)
                  Positioned(
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                        child: Text(
                          _faceDetected
                            ? 'Face not aligned to guide'
                            : 'No face detected',
                          style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.white)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Status message
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _activeStatusMessage(),
              key: ValueKey(_activeStatusMessage()),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _phase == CheckInPhase.success
                    ? AppColors.success
                    : _phase == CheckInPhase.error
                        ? AppColors.error
                        : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  // Challenge status list
  // ----------------------------------------------------------------
  Widget _buildChallengeList() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Liveness Challenges',
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
          const SizedBox(height: 12),
          ...List.generate(_challenges.length, (i) {
            final challenge = _challenges[i];
            final passed = _challengeResults[i];
            final isCurrent =
                i == _currentChallengeIndex &&
                _phase == CheckInPhase.scanning;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: passed
                          ? AppColors.success.withValues(alpha: 0.2)
                          : isCurrent
                              ? AppColors.primary
                                  .withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.05),
                      border: Border.all(
                        color: passed
                            ? AppColors.success
                            : isCurrent
                                ? AppColors.primary
                                : Colors.white24,
                        width: 1.5,
                      ),
                    ),
                    child: passed
                        ? const Icon(Icons.check,
                            size: 16, color: AppColors.success)
                        : isCurrent
                            ? const Icon(Icons.radio_button_checked,
                                size: 14, color: AppColors.primary)
                            : Center(
                                child: Text('${i + 1}',
                                    style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: Colors.white38)),
                              ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      FaceRecognitionService.challengeInstruction(
                          challenge),
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: passed
                            ? AppColors.success
                            : isCurrent
                                ? Colors.white
                                : Colors.white38,
                        fontWeight: isCurrent
                            ? FontWeight.w600
                            : FontWeight.w400,
                        decoration: passed
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
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
  // Verification card
  // ----------------------------------------------------------------
  Widget _buildVerificationCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_user,
                color: AppColors.success, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Identity Verified',
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.success)),
                Text(
                    '${_verificationConfidence.toStringAsFixed(1)}% match',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.white60)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  // GPS card
  // ----------------------------------------------------------------
  Widget _buildGPSCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _position != null
                  ? Icons.location_on
                  : Icons.location_searching,
              color: AppColors.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    _position != null
                        ? 'Location Captured'
                        : 'Capturing Location...',
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent)),
                if (_address.isNotEmpty)
                  Text(_address,
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: Colors.white60),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                if (_position != null)
                  Text(
                      '${_position!.latitude.toStringAsFixed(4)}, '
                      '${_position!.longitude.toStringAsFixed(4)}',
                      style: GoogleFonts.poppins(
                          fontSize: 11, color: Colors.white38)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  // Error card
  // ----------------------------------------------------------------
  Widget _buildErrorCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline,
              color: AppColors.error, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(_errorMessage,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  // Bottom action button (fixed)
  // ----------------------------------------------------------------
  Widget _buildBottomButton() {
    String label;
    VoidCallback? onPressed;
    Color bgColor;

    switch (_phase) {
      case CheckInPhase.initializing:
        label = 'Initializing...';
        onPressed = null;
        bgColor = Colors.grey;
        break;
      case CheckInPhase.scanning:
        label = 'Scanning Face...';
        onPressed = null;
        bgColor = AppColors.primary.withValues(alpha: 0.5);
        break;
      case CheckInPhase.verifying:
        label = 'Verifying...';
        onPressed = null;
        bgColor = AppColors.primary.withValues(alpha: 0.5);
        break;
      case CheckInPhase.gps:
        label = 'Capturing Location...';
        onPressed = null;
        bgColor = AppColors.accent.withValues(alpha: 0.5);
        break;
      case CheckInPhase.success:
        label = 'Done ✓';
        onPressed = _handleDone;
        bgColor = AppColors.success;
        break;
      case CheckInPhase.error:
        label = 'Retry';
        onPressed = _retry;
        bgColor = AppColors.warning;
        break;
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: bgColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}
