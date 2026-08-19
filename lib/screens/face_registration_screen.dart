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
import '../services/auth_service.dart';
import '../utils/camera_input_image.dart';
import '../widgets/face_capture_stage.dart';

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
  final _authService = AuthService();
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
  static const int _requiredHoldFrames = 5;
  static const Duration _firstPositioningWindow = Duration(seconds: 2);
  static const Duration _postCaptureSettle = Duration(milliseconds: 600);
  static const String _positioningMessage =
      'Position your face in the oval…';
  DateTime? _analysisArmedAt;
  bool _isFirstStreamStart = true;
  double _progress = 0.0;
  double _animatedProgress = 0.0;
  double _progressAnimationStart = 0.0;

  final List<bool> _captureResults =
      List.filled(FaceRecognitionService.registrationCaptures, false);

  // ---- Frame analysis ----
  bool _processingFrame = false;
  bool _isStreamActive = false;
  DateTime? _lastStreamProcessed;
  int _nullInputFrameCount = 0;
  static const int _nullInputFrameThreshold = 10;
  int _streamFrameWidth = 0;
  int _streamFrameHeight = 0;

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
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();

      if (!mounted) return;
      setState(() {
        _cameraReady = true;
        _statusMessage =
            FaceRecognitionService.angleInstruction(_targetAngle);
      });

      _startImageStream();
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Camera error: $e');
    }
  }

  Future<void> _startImageStream() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized || _isStreamActive) {
      return;
    }
    try {
      await controller.startImageStream(_onCameraImage);
      _isStreamActive = true;
      final isFirst = _isFirstStreamStart;
      _isFirstStreamStart = false;
      _analysisArmedAt = DateTime.now().add(
        isFirst ? _firstPositioningWindow : _postCaptureSettle,
      );
      _angleHoldFrames = 0;
      if (isFirst && mounted) {
        setState(() => _statusMessage = _positioningMessage);
      }
    } catch (e) {
      debugPrint('Image stream start failed: $e');
      if (mounted) {
        setState(() {
          _statusMessage =
              'Camera stream failed. Close other camera apps and retry.';
        });
      }
    }
  }

  Future<void> _stopImageStream() async {
    final controller = _cameraController;
    if (controller == null || !_isStreamActive) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (e) {
      debugPrint('Image stream stop failed: $e');
    } finally {
      _isStreamActive = false;
    }
  }

  @override
  void dispose() {
    _stopImageStream();
    _cameraController?.dispose();
    _captureFlashAnim.dispose();
    _progressAnim.dispose();
    _tickAnim.dispose();
    super.dispose();
  }

  // ================================================================
  // Frame analysis
  // ================================================================

  Future<void> _onCameraImage(CameraImage image) async {
    if (_processingFrame ||
        _isCapturing ||
        _isCompleted ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }

    final now = DateTime.now();
    if (_lastStreamProcessed != null &&
        now.difference(_lastStreamProcessed!) <
            const Duration(milliseconds: 200)) {
      return;
    }
    _lastStreamProcessed = now;
    _processingFrame = true;

    try {
      final armedAt = _analysisArmedAt;
      if (armedAt != null && now.isBefore(armedAt)) {
        if (mounted) {
          setState(() {
            _angleHoldFrames = 0;
            if (_currentCapture == 0 && !_captureResults[0]) {
              _statusMessage = _positioningMessage;
            }
          });
        }
        return;
      }

      final controller = _cameraController!;
      final frameDimensions =
          CameraInputImage.effectiveDimensions(image, controller);

      final inputImage = CameraInputImage.fromCameraImage(image, controller);
      if (inputImage == null) {
        _nullInputFrameCount++;
        if (_nullInputFrameCount >= _nullInputFrameThreshold && mounted) {
          setState(() {
            _faceDetected = false;
            _facePlacedCorrectly = false;
            _angleHoldFrames = 0;
            _statusMessage =
                'Camera format not supported — close and reopen this screen';
          });
        }
        return;
      }
      _nullInputFrameCount = 0;
      _streamFrameWidth = frameDimensions.width;
      _streamFrameHeight = frameDimensions.height;

      final faces = await _faceService.detectFacesLive(inputImage);
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

        setState(() {
          _faceDetected = true;
          _facePlacedCorrectly = true;
        });

        if (_faceService.isTargetAngle(face, _targetAngle)) {
          _angleHoldFrames++;
          if (_angleHoldFrames >= _requiredHoldFrames) {
            setState(() => _statusMessage = 'Capturing...');
            await _captureFromCamera();
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
      _processingFrame = false;
    }
  }

  Future<void> _waitForCameraIdle({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (!controller.value.isStreamingImages &&
          !controller.value.isTakingPicture) {
        await Future.delayed(const Duration(milliseconds: 200));
        return;
      }
      await Future.delayed(const Duration(milliseconds: 40));
    }
  }

  Future<void> _captureFromCamera() async {
    await _stopImageStream();
    _isCapturing = true;
    _captureFlashAnim.forward().then((_) => _captureFlashAnim.reverse());
    await _waitForCameraIdle();

    File? imageFile;
    try {
      final xFile = await _cameraController?.takePicture();
      if (xFile == null) {
        setState(() {
          _angleHoldFrames = 0;
          _statusMessage = 'Capture failed. Try again.';
        });
        return;
      }
      imageFile = File(xFile.path);
      await _captureRegistration(imageFile);
      imageFile = null;
    } catch (e) {
      setState(() {
        _angleHoldFrames = 0;
        _statusMessage = 'Capture failed. Try again.';
      });
    } finally {
      _isCapturing = false;
      if (!_isCompleted) {
        await _startImageStream();
      }
      try {
        await imageFile?.delete();
      } catch (_) {}
    }
  }

  String? _facePlacementIssue(Face face) {
    final dimensions = _streamFrameDimensions();
    if (dimensions == null) {
      return 'Hold still while the camera focuses';
    }

    final placement = _faceService.evaluateLivePlacement(
      face,
      dimensions.width,
      dimensions.height,
    );
    if (placement.isFrontCamera) return null;
    return placement.issue ?? 'Fill the face guide';
  }

  // Live stream uses placement only; strict quality runs at capture time.

  ({int width, int height})? _streamFrameDimensions() {
      if (_streamFrameWidth > 0 && _streamFrameHeight > 0) {
        return (width: _streamFrameWidth, height: _streamFrameHeight);
      }
      return _resolvePreviewDimensions();
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
            final profile = await _authService.getCurrentUserProfile();
            savedToBackend = await _faceRegistrationApiService
                .saveFaceRegistration(
              registrationData,
              canonicalEmployeeId: profile?.canonicalEmployeeId,
            );
          }

          await _stopImageStream();
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
    final guideColor = _faceDetected
        ? (_facePlacedCorrectly && _angleHoldFrames > 0
            ? AppColors.success
            : _facePlacedCorrectly
                ? AppColors.primary
                : AppColors.warning)
        : Colors.white54;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          FaceCaptureStage(
            height: height,
            cameraReady: _cameraReady,
            cameraController: _cameraController,
            progress: _animatedProgress,
            guideColor: guideColor,
            isMatching: _angleHoldFrames > 0,
            showSuccessTick: _progress >= 1.0 && !_isCompleted,
            tickScale: _tickScale,
            coachingMessage: _isCompleted ? null : _statusMessage,
            coachingIcon: _coachingIcon,
            topBadge: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                  color: Colors.white,
                ),
              ),
            ),
            flash: FadeTransition(
              opacity: _captureFlashAnim,
              child: const ColoredBox(color: Colors.white),
            ),
          ),
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
                  Text(
                    'Registration Complete!',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  IconData get _coachingIcon {
    final message = _statusMessage.toLowerCase();
    if (!_faceDetected) return Icons.face_retouching_off_outlined;
    if (message.contains('too close')) return Icons.zoom_out_rounded;
    if (message.contains('closer') || message.contains('too small')) {
      return Icons.zoom_in_rounded;
    }
    if (message.contains('center')) return Icons.center_focus_strong_rounded;
    if (!_facePlacedCorrectly) return Icons.zoom_in_rounded;
    return Icons.center_focus_strong_rounded;
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
