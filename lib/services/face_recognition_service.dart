import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/face_registration_data.dart';

/// Face angle for registration and verification challenges
enum FaceAngle { straight, left, right, up, down, unknown }

/// Challenge types for check-in verification
enum ChallengeType { lookStraight, smile, blink, turnLeft, turnRight }

class FaceRecognitionService {
  static final FaceRecognitionService _instance =
      FaceRecognitionService._internal();
  factory FaceRecognitionService() => _instance;
  FaceRecognitionService._internal();

  Interpreter? _interpreter;
  late FaceDetector _liveFaceDetector;
  late FaceDetector _finalFaceDetector;
  bool _isInitialized = false;

  /// The single place to swap the recogniser. Any TFLite face-embedding model
  /// works: the input size and embedding length are read from the model's own
  /// tensors in [initialize], and [templateVersion] must be bumped when the model
  /// changes so every device re-enrols rather than comparing a new-model probe
  /// against an old-model template.
  static const String _modelAsset = 'assets/models/ghostfacenet.tflite';

  /// Fallbacks, used only when the loaded model reports an unexpected shape.
  static const int _defaultInputSize = 112;
  static const int defaultEmbeddingSize = 192;

  /// Set from the loaded model's input tensor (square models only; alignment
  /// assumes 112 and is skipped otherwise).
  int _inputSize = _defaultInputSize;

  /// Set from the loaded model's output tensor length (192 for MobileFaceNet,
  /// 512 for GhostFaceNet/ArcFace).
  int embeddingSize = defaultEmbeddingSize;

  /// Bumped whenever the embedding pipeline changes shape or preprocessing
  /// (model, alignment, normalisation). A stored template with a different
  /// version is rejected instead of silently mis-matched.
  /// 4 = GhostFaceNet W1.3 S2 ArcFace, 512-d (3 = landmark-aligned 192-d crop,
  /// 2 = padded bounding-box crop).
  static const int templateVersion = 4;

  // --- Thresholds for the current model (GhostFaceNet W1.3 S2 ArcFace, 512-d) ---
  // ArcFace-margin models cluster each identity tightly and push different people
  // far apart, so the *absolute* cosine bar sits lower than MobileFaceNet's while
  // still rejecting impostors. Starting values — calibrate against a labelled set
  // before trusting them.

  // Core match threshold against registration templates (avg + captures).
  static const double _matchThreshold = 0.55;

  // Strong core-template match threshold
  static const double _strongMatchThreshold = 0.68;

  // How many of the enrolled templates must clear the consistency bar. One is
  // not enough when a template set holds several poses (or people); require a
  // majority-ish agreement so a single lucky template cannot carry a match.
  static const int _requiredCoreHits = 2;

  // Same-person threshold: a registration capture must match the running
  // average of the captures already taken, so a second person cannot slip into a
  // shared account's template set.
  static const double _samePersonThreshold = 0.62;

  // Relaxed threshold for extreme registration poses (up/down)
  static const double _samePersonExtremeAngleThreshold = 0.50;

  // Minimum smile probability for liveness "smile" challenge
  static const double _smileThreshold = 0.55;

  // Minimum face-to-image area ratio for live preview and still capture.
  static const double minAcceptableFaceRatio = 0.16;

  // Faces below this ratio get a quality penalty but are not auto-rejected.
  static const double minPreferredFaceRatio = 0.20;

  // Live too-close ceiling so the face is not cropped by the guide.
  static const double maxLiveFaceRatio = 0.55;

  // Live centering vs full frame (guide half-width is ~0.31).
  static const double liveCenterTolerance = 0.20;

  // Still JPEG centering. Angled poses may sit slightly off-axis.
  static const double stillCenterTolerance = 0.25;
  static const double stillAngledCenterTolerance = 0.28;

  // Liveness: minimum edge sharpness score (photos-of-screens are blurrier)
  static const double _minSharpnessScore = 15.0;

  // Number of images to capture during registration for robustness
  static const int registrationCaptures = 5;

  // Registration angle sequence
  static const List<FaceAngle> registrationAngles = [
    FaceAngle.straight,
    FaceAngle.left,
    FaceAngle.right,
    FaceAngle.up,
    FaceAngle.down,
  ];

  List<List<double>> _registeredEmbeddings = <List<double>>[];
  List<double>? _registeredAvgEmbedding;
  List<List<double>> _adaptiveEmbeddings = <List<double>>[];
  String? _registrationTime;
  int _registrationCaptureCount = 0;

  void hydrateRegistration(FaceRegistrationData? registration) {
    if (registration == null || !registration.hasValidTemplates) {
      clearRegistrationMemory();
      return;
    }

    // A template built by a different pipeline (e.g. the old padded-crop
    // embeddings) cannot be compared against this engine's probe. Drop it so the
    // officer is asked to re-enrol once rather than failing every match — but
    // only when the stored version is *known* to differ. 0 means the server did
    // not record a version (a row written before the column existed); that is
    // accepted here, and a genuinely older model's template is still caught by
    // the length guard in verifyFace.
    final storedVersion = registration.templateVersion;
    if (storedVersion > 0 && storedVersion != templateVersion) {
      clearRegistrationMemory();
      return;
    }

    _registeredAvgEmbedding = List<double>.from(registration.avgEmbedding);
    _registeredEmbeddings = registration.captureEmbeddings
        .map((row) => List<double>.from(row))
        .toList();
    if (_registeredEmbeddings.isEmpty && _registeredAvgEmbedding != null) {
      _registeredEmbeddings = [List<double>.from(_registeredAvgEmbedding!)];
    }
    _adaptiveEmbeddings = registration.adaptiveEmbeddings
        .map((row) => List<double>.from(row))
        .toList();
    _registrationCaptureCount = registration.captureCount;
    _registrationTime = registration.registeredAt;
  }

  FaceRegistrationData? exportRegistrationData() {
    if (!FaceRegistrationData.isValidEmbedding(_registeredAvgEmbedding, expectedSize: null)) {
      return null;
    }

    return FaceRegistrationData(
      avgEmbedding: List<double>.from(_registeredAvgEmbedding!),
      captureEmbeddings: _registeredEmbeddings
          .map((row) => List<double>.from(row))
          .toList(),
      adaptiveEmbeddings: _adaptiveEmbeddings
          .map((row) => List<double>.from(row))
          .toList(),
      captureCount: _registrationCaptureCount,
      templateVersion: templateVersion,
      registeredAt: _registrationTime,
      registrationQuality: null,
      status: 'active',
    );
  }

  void clearRegistrationMemory() {
    _registeredAvgEmbedding = null;
    _registeredEmbeddings = <List<double>>[];
    _adaptiveEmbeddings = <List<double>>[];
    _registrationTime = null;
    _registrationCaptureCount = 0;
  }

  /// Initialize the service: load TFLite model & face detector
  Future<void> initialize() async {
    if (_isInitialized) return;

    _interpreter = await Interpreter.fromAsset(_modelAsset);
    _applyModelShape();

    _liveFaceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: false,
        enableLandmarks: true,
        enableClassification: true,
        enableTracking: false,
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.12,
      ),
    );

    _finalFaceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: false,
        enableLandmarks: true,
        enableClassification: true,
        enableTracking: false,
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.15,
      ),
    );

    _isInitialized = true;
  }

  /// Read the input / output size straight off the loaded model so a swapped
  /// `.tflite` works with no code change. Falls back to the defaults when the
  /// tensor shapes are not the expected square-image / flat-vector form.
  void _applyModelShape() {
    final interpreter = _interpreter;
    if (interpreter == null) return;
    try {
      final inputShape = interpreter.getInputTensor(0).shape; // [1, h, w, 3]
      if (inputShape.length == 4 &&
          inputShape[1] > 0 &&
          inputShape[1] == inputShape[2]) {
        _inputSize = inputShape[1];
      }
      final outputShape = interpreter.getOutputTensor(0).shape; // [1, n]
      final outputSize = outputShape.isEmpty ? 0 : outputShape.last;
      if (outputSize > 0) {
        embeddingSize = outputSize;
      }
    } catch (_) {
      // Keep the defaults; the model still runs with 112 / 192.
    }
  }

  /// Detect faces in an image file. Returns list of Face objects.
  Future<List<Face>> detectFaces(File imageFile) async {
    if (!_isInitialized) await initialize();
    final inputImage = InputImage.fromFile(imageFile);
    return await _finalFaceDetector.processImage(inputImage);
  }

  /// Fast live detection from a camera stream frame.
  Future<List<Face>> detectFacesLive(InputImage inputImage) async {
    if (!_isInitialized) await initialize();
    return await _liveFaceDetector.processImage(inputImage);
  }

  // ---- Liveness Detection ----

  /// Perform liveness checks on a face image.
  /// [requireSmile] — if true, the user must be smiling.
  /// Returns a LivenessResult with pass/fail and reasons.
  Future<LivenessResult> checkLiveness(
    File imageFile, {
    bool requireSmile = false,
  }) async {
    if (!_isInitialized) await initialize();

    final faces = await detectFaces(imageFile);
    if (faces.isEmpty) {
      return LivenessResult(
        isLive: false,
        issues: ['No face detected in the image.'],
        smileProbability: 0,
        sharpnessScore: 0,
      );
    }

    final face = faces.first;
    final issues = <String>[];

    // 1. Check that exactly one face is present (multi-face = showing a group photo)
    if (faces.length > 1) {
      issues.add('Multiple faces detected — only your face should be visible.');
    }

    // 2. Smile challenge
    final smileProb = face.smilingProbability ?? 0.0;
    if (requireSmile && smileProb < _smileThreshold) {
      issues.add(
          'Smile not detected (${(smileProb * 100).toStringAsFixed(0)}%). Please smile clearly for liveness verification.');
    }

    // 3. Eye openness (both eyes must be open — closed eyes suggest a photo)
    final leftEye = face.leftEyeOpenProbability ?? 1.0;
    final rightEye = face.rightEyeOpenProbability ?? 1.0;
    if (leftEye < 0.4 && rightEye < 0.4) {
      issues.add('Both eyes appear closed — this may indicate a still photo.');
    }

    // 4. Face size check (selfie = large face; photo of screen = smaller face)
    final bytes = await imageFile.readAsBytes();
    final rawImage = img.decodeImage(bytes);
    double sharpness = 0;

    if (rawImage != null) {
      final faceArea = face.boundingBox.width * face.boundingBox.height;
      final imageArea = rawImage.width * rawImage.height;
      final faceRatio = faceArea / imageArea;

      if (faceRatio < minAcceptableFaceRatio) {
        issues.add(
            'Face is too small — hold the phone closer or use the front camera.');
      }

      // 5. Sharpness / texture analysis using Laplacian variance
      // Photos of screens have lower edge contrast due to pixel grid / moire
      sharpness = _calculateSharpness(rawImage, face.boundingBox);
      if (sharpness < _minSharpnessScore) {
        issues.add(
            'Image quality too low — possible photo of a screen detected. Please use a live face.');
      }
    }

    // 6. Head has some natural 3D depth cues — small Euler angle variance
    // A perfectly flat photo shown to camera tends to have very consistent angles
    // We can't detect this from a single image, but we trust ML Kit's detection confidence

    return LivenessResult(
      isLive: issues.isEmpty,
      issues: issues,
      smileProbability: smileProb,
      sharpnessScore: sharpness,
    );
  }

  /// Calculate image sharpness using Laplacian variance on the face region.
  /// Higher values = sharper image (real face). Lower = blurry (photo of screen).
  double _calculateSharpness(img.Image image, Rect faceBox) {
    // Crop to face region
    final x = faceBox.left.toInt().clamp(0, image.width - 1);
    final y = faceBox.top.toInt().clamp(0, image.height - 1);
    final w = faceBox.width.toInt().clamp(1, image.width - x);
    final h = faceBox.height.toInt().clamp(1, image.height - y);

    final faceImg = img.copyCrop(image, x: x, y: y, width: w, height: h);

    // Resize to small size for fast computation
    final small = img.copyResize(faceImg, width: 64, height: 64);

    // Convert to grayscale values
    final gray = List.generate(
        64, (y) => List.generate(64, (x) {
          final p = small.getPixel(x, y);
          return (p.r * 0.299 + p.g * 0.587 + p.b * 0.114);
        }));

    // Compute Laplacian (simple 3x3 kernel: 0 1 0 / 1 -4 1 / 0 1 0)
    double sumSq = 0;
    int count = 0;
    for (int y = 1; y < 63; y++) {
      for (int x = 1; x < 63; x++) {
        final lap = gray[y - 1][x] +
            gray[y + 1][x] +
            gray[y][x - 1] +
            gray[y][x + 1] -
            4 * gray[y][x];
        sumSq += lap * lap;
        count++;
      }
    }

    return count > 0 ? sumSq / count : 0;
  }

  // ---- Back Camera Detection ----

  /// Check if the image appears to be from the front camera (selfie).
  /// Front camera selfies have a large, centered face.
  FrontCameraCheckResult checkFrontCamera(
    Face face,
    int imageWidth,
    int imageHeight, {
    bool requireCentering = true,
    double centerTolerance = 0.3,
    bool forLiveGuidance = false,
  }) {
    final faceArea = face.boundingBox.width * face.boundingBox.height;
    final imageArea = imageWidth * imageHeight;
    final faceRatio = imageArea <= 0 ? 0.0 : faceArea / imageArea;
    final ratioIssue = faceFramingIssue(
      faceRatio,
      forLiveGuidance: forLiveGuidance,
    );

    final faceCenterX = face.boundingBox.center.dx / imageWidth;
    final faceCenterY = face.boundingBox.center.dy / imageHeight;
    final isCentered =
        (faceCenterX - 0.5).abs() < centerTolerance &&
        (faceCenterY - 0.5).abs() < centerTolerance;

    final isFrontCamera =
        ratioIssue == null && (!requireCentering || isCentered);

    String? issue = ratioIssue;
    if (issue == null && requireCentering && !isCentered) {
      issue = 'Center your face inside the guide';
    }

    return FrontCameraCheckResult(
      isFrontCamera: isFrontCamera,
      faceRatio: faceRatio,
      issue: issue,
    );
  }

  /// Size gate used by live preview and still capture (no ML Kit needed).
  static String? faceFramingIssue(
    double faceRatio, {
    required bool forLiveGuidance,
  }) {
    if (faceRatio < minAcceptableFaceRatio) {
      return forLiveGuidance
          ? 'Move closer and fill the face guide'
          : 'Face appears too small — please use the front camera and hold the phone closer.';
    }
    if (forLiveGuidance && faceRatio > maxLiveFaceRatio) {
      return 'Move back a little — your face is too close';
    }
    return null;
  }

  static bool isFaceRatioAcceptable(
    double faceRatio, {
    required bool forLiveGuidance,
  }) {
    return faceFramingIssue(
          faceRatio,
          forLiveGuidance: forLiveGuidance,
        ) ==
        null;
  }

  /// Live placement with a width/height swap fallback for inverted frames.
  FrontCameraCheckResult evaluateLivePlacement(
    Face face,
    int imageWidth,
    int imageHeight,
  ) {
    final primary = checkFrontCamera(
      face,
      imageWidth,
      imageHeight,
      requireCentering: true,
      centerTolerance: liveCenterTolerance,
      forLiveGuidance: true,
    );
    if (primary.isFrontCamera || imageWidth == imageHeight) {
      return primary;
    }

    final box = face.boundingBox;
    final primaryFits =
        box.right <= imageWidth + 1 && box.bottom <= imageHeight + 1;
    final swappedFits =
        box.right <= imageHeight + 1 && box.bottom <= imageWidth + 1;
    if (primaryFits || !swappedFits) {
      return primary;
    }

    final swapped = checkFrontCamera(
      face,
      imageHeight,
      imageWidth,
      requireCentering: true,
      centerTolerance: liveCenterTolerance,
      forLiveGuidance: true,
    );
    return swapped.isFrontCamera ? swapped : primary;
  }

  // ---- Same Person Validation ----

  /// Check if a new embedding matches all previously registered embeddings.
  /// Returns true if the new face is the same person as all existing captures.
  bool isSamePerson(List<double> newEmbedding, List<List<double>> existingEmbeddings) {
    for (final existing in existingEmbeddings) {
      final similarity = _cosineSimilarity(newEmbedding, existing);
      if (similarity < _samePersonThreshold) {
        return false;
      }
    }
    return true;
  }

  double _requiredSamePersonThreshold(FaceAngle? targetAngle) {
    if (targetAngle == FaceAngle.up || targetAngle == FaceAngle.down) {
      return _samePersonExtremeAngleThreshold;
    }
    return _samePersonThreshold;
  }

  // ---- Face Angle & Challenge Detection ----

  /// Detect the current face angle from ML Kit euler angles
  FaceAngle detectFaceAngle(Face face) {
    final yaw = face.headEulerAngleY ?? 0;
    final pitch = face.headEulerAngleX ?? 0;

    if (yaw.abs() < 14 && pitch.abs() < 14) return FaceAngle.straight;

    if (yaw.abs() > pitch.abs()) {
      if (yaw > 16) return FaceAngle.left;
      if (yaw < -16) return FaceAngle.right;
    } else {
      if (pitch > 10) return FaceAngle.up;
      if (pitch < -6) return FaceAngle.down;
    }

    return FaceAngle.unknown;
  }

  /// Check if face matches a target angle with tolerance
  bool isTargetAngle(Face face, FaceAngle target) {
    final yaw = face.headEulerAngleY;
    final pitch = face.headEulerAngleX;

    switch (target) {
      case FaceAngle.straight:
        if (yaw == null || pitch == null) return false;
        return yaw.abs() < 14 && pitch.abs() < 14;
      case FaceAngle.left:
        return (yaw ?? 0) > 15 && (yaw ?? 0) < 55;
      case FaceAngle.right:
        return (yaw ?? 0) < -15 && (yaw ?? 0) > -55;
      case FaceAngle.up:
        return (pitch ?? 0) > 9 && (pitch ?? 0) < 45;
      case FaceAngle.down:
        return (pitch ?? 0) < -6 && (pitch ?? 0) > -70;
      case FaceAngle.unknown:
        return false;
    }
  }

  /// Check if user is smiling (for liveness challenge)
  bool isSmiling(Face face) {
    return (face.smilingProbability ?? 0) >= _smileThreshold;
  }

  /// Check if both eyes are closed (for blink detection)
  bool areEyesClosed(Face face) {
    final leftEye = face.leftEyeOpenProbability ?? 1.0;
    final rightEye = face.rightEyeOpenProbability ?? 1.0;
    return leftEye < 0.3 && rightEye < 0.3;
  }

  /// Check if both eyes are open
  bool areEyesOpen(Face face) {
    final leftEye = face.leftEyeOpenProbability ?? 1.0;
    final rightEye = face.rightEyeOpenProbability ?? 1.0;
    return leftEye > 0.5 && rightEye > 0.5;
  }

  /// Detect faces from an InputImage (for live camera frames)
  Future<List<Face>> detectFacesFromInputImage(InputImage inputImage) async {
    return detectFacesLive(inputImage);
  }

  /// Get human-readable name for a face angle
  static String angleDisplayName(FaceAngle angle) {
    switch (angle) {
      case FaceAngle.straight: return 'Look Straight';
      case FaceAngle.left: return 'Turn Left';
      case FaceAngle.right: return 'Turn Right';
      case FaceAngle.up: return 'Look Up';
      case FaceAngle.down: return 'Look Down';
      case FaceAngle.unknown: return 'Adjust Position';
    }
  }

  /// Get instruction text for a face angle during registration
  static String angleInstruction(FaceAngle angle) {
    switch (angle) {
      case FaceAngle.straight: return 'Look straight at the camera';
      case FaceAngle.left: return 'Slowly turn your face to the left';
      case FaceAngle.right: return 'Slowly turn your face to the right';
      case FaceAngle.up: return 'Slightly tilt your head upward';
      case FaceAngle.down: return 'Slightly tilt your head downward';
      case FaceAngle.unknown: return 'Position your face in the guide';
    }
  }

  /// Get instruction text for a check-in challenge
  static String challengeInstruction(ChallengeType challenge) {
    switch (challenge) {
      case ChallengeType.lookStraight: return 'Look straight at the camera';
      case ChallengeType.smile: return 'Smile! 😄';
      case ChallengeType.blink: return 'Blink your eyes';
      case ChallengeType.turnLeft: return 'Turn your face slightly left';
      case ChallengeType.turnRight: return 'Turn your face slightly right';
    }
  }

  /// Check quality of a detected face. Returns a FaceQualityResult.
  FaceQualityResult checkFaceQuality(
    Face face,
    int imageWidth,
    int imageHeight, {
    bool skipRotationCheck = false,
    bool forLiveGuidance = false,
  }) {
    final issues = <String>[];
    double score = 100.0;

    // 1. Face size check
    final faceArea = face.boundingBox.width * face.boundingBox.height;
    final imageArea = imageWidth * imageHeight;
    final faceRatio = faceArea / imageArea;

    if (faceRatio < minAcceptableFaceRatio) {
      issues.add('Face is too far — move closer to the camera');
      score -= 40;
    } else if (faceRatio < minPreferredFaceRatio) {
      issues.add('Face is a bit far — move slightly closer');
      score -= 20;
    }

    if (forLiveGuidance && faceRatio > maxLiveFaceRatio) {
      issues.add('Face is too close — move back a little');
      score -= 20;
    } else if (!forLiveGuidance && faceRatio > 0.70) {
      issues.add('Face is too close — move back a little');
      score -= 20;
    }

    // 2. Head rotation check
    final yaw = face.headEulerAngleY ?? 0;
    final pitch = face.headEulerAngleX ?? 0;
    final roll = face.headEulerAngleZ ?? 0;

    if (!skipRotationCheck) {
      if (yaw.abs() > 25) {
        issues.add('Face is turned too far ${yaw > 0 ? "left" : "right"} — look straight at camera');
        score -= 30;
      } else if (yaw.abs() > 15) {
        issues.add('Slight head turn detected — try to face the camera directly');
        score -= 15;
      }

      if (pitch.abs() > 20) {
        issues.add('Face is tilted ${pitch > 0 ? "down" : "up"} — hold phone at eye level');
        score -= 25;
      }

      if (roll.abs() > 15) {
        issues.add('Head is tilted sideways — keep your head straight');
        score -= 15;
      }
    }

    // 3. Face centering check
    final faceCenterX = face.boundingBox.center.dx / imageWidth;
    final faceCenterY = face.boundingBox.center.dy / imageHeight;

    if ((faceCenterX - 0.5).abs() > 0.25 || (faceCenterY - 0.5).abs() > 0.25) {
      issues.add('Face is off-center — position your face in the guide');
      score -= 20;
    }

    // 4. Eye open check
    final leftEyeOpen = face.leftEyeOpenProbability ?? 1.0;
    final rightEyeOpen = face.rightEyeOpenProbability ?? 1.0;
    final minEyeOpenThreshold = skipRotationCheck ? 0.35 : 0.5;
    if (leftEyeOpen < minEyeOpenThreshold ||
        rightEyeOpen < minEyeOpenThreshold) {
      issues.add('Eyes appear closed — please open your eyes');
      score -= 20;
    }

    final minScore = forLiveGuidance ? 40.0 : 50.0;
    final framingOk = faceRatio >= minAcceptableFaceRatio &&
        !(forLiveGuidance && faceRatio > maxLiveFaceRatio);

    return FaceQualityResult(
      score: score.clamp(0.0, 100.0),
      issues: issues,
      isAcceptable: score >= minScore && framingOk,
      faceRatio: faceRatio,
      yaw: yaw,
      pitch: pitch,
    );
  }

  /// Generate a 192-dim face embedding from an image file.
  /// Set [checkQuality] to true to reject poor quality faces.
  /// Set [checkLivenessSmile] to true to require a smile for liveness.
  /// Set [checkFrontCam] to true to reject images not from front camera.
  Future<EmbeddingResult> generateEmbedding(
    File imageFile, {
    bool checkQuality = false,
    bool checkLivenessSmile = false,
    bool checkFrontCam = false,
    bool requireFrontCamCentering = true,
    double? frontCamCenterTolerance,
    bool skipRotationCheck = false,
    bool robustEmbedding = true,
  }) async {
    if (!_isInitialized) await initialize();

    // 1. Detect face
    final faces = await detectFaces(imageFile);
    if (faces.isEmpty) {
      return EmbeddingResult(embedding: null, quality: null, error: 'No face detected');
    }

    if (faces.length > 1) {
      return EmbeddingResult(
        embedding: null,
        quality: null,
        error: 'Multiple faces detected — only your face should be visible.',
      );
    }

    // 2. Read and decode image
    final bytes = await imageFile.readAsBytes();
    final rawImage = img.decodeImage(bytes);
    if (rawImage == null) {
      return EmbeddingResult(embedding: null, quality: null, error: 'Could not decode image');
    }

    final face = faces.first;

    // 3. Front camera check
    if (checkFrontCam) {
      final camCheck = checkFrontCamera(
        face,
        rawImage.width,
        rawImage.height,
        requireCentering: requireFrontCamCentering,
        centerTolerance: frontCamCenterTolerance ?? stillCenterTolerance,
      );
      if (!camCheck.isFrontCamera) {
        return EmbeddingResult(
          embedding: null,
          quality: null,
          error: camCheck.issue ?? 'Please use the front camera for a selfie.',
        );
      }
    }

    // 4. Quality check
    FaceQualityResult? quality;
    if (checkQuality) {
      quality = checkFaceQuality(face, rawImage.width, rawImage.height, skipRotationCheck: skipRotationCheck);
      if (!quality.isAcceptable) {
        return EmbeddingResult(
          embedding: null,
          quality: quality,
          error: quality.issues.isNotEmpty ? quality.issues.first : 'Poor face quality',
        );
      }
    }

    // 5. Liveness: sharpness check (always on)
    final sharpness = _calculateSharpness(rawImage, face.boundingBox);
    if (sharpness < _minSharpnessScore) {
      return EmbeddingResult(
        embedding: null,
        quality: quality,
        error: 'Image quality too low — possible photo of a screen detected. Use a live face.',
      );
    }

    // 6. Liveness: smile check (when required)
    if (checkLivenessSmile) {
      final smileProb = face.smilingProbability ?? 0.0;
      if (smileProb < _smileThreshold) {
        return EmbeddingResult(
          embedding: null,
          quality: quality,
          error: 'Smile not detected (${(smileProb * 100).toStringAsFixed(0)}%). Please smile clearly for liveness check.',
        );
      }
    }

    // 7. Align the face to the canonical template when the landmarks allow it;
    // fall back to the padded bounding-box crop otherwise.
    final croppedFace =
        _alignFace(rawImage, face) ?? _cropFace(rawImage, face.boundingBox);

    // 8. Generate embedding (single pass for speed, robust for final match)
    final embedding = robustEmbedding
        ? _generateRobustEmbedding(croppedFace)
        : _embeddingFromFaceImage(croppedFace);

    // 9. L2 normalize and return
    return EmbeddingResult(
      embedding: _l2Normalize(embedding),
      quality: quality,
      error: null,
    );
  }

  /// Crop the face from the image with generous padding
  img.Image _cropFace(img.Image image, Rect boundingBox) {
    final padW = (boundingBox.width * 0.40).toInt();
    final padH = (boundingBox.height * 0.40).toInt();

    int x = (boundingBox.left - padW).toInt().clamp(0, image.width - 1);
    int y = (boundingBox.top - padH).toInt().clamp(0, image.height - 1);
    int w = (boundingBox.width + padW * 2).toInt().clamp(1, image.width - x);
    int h = (boundingBox.height + padH * 2).toInt().clamp(1, image.height - y);

    if (w > h) {
      final diff = w - h;
      y = (y - diff ~/ 2).clamp(0, image.height - 1);
      h = w.clamp(1, image.height - y);
    } else if (h > w) {
      final diff = h - w;
      x = (x - diff ~/ 2).clamp(0, image.width - 1);
      w = h.clamp(1, image.width - x);
    }

    return img.copyCrop(image, x: x, y: y, width: w, height: h);
  }

  // ---- Landmark alignment ----

  /// Canonical 5-point face template (ArcFace, 112×112), in order:
  /// left eye, right eye, nose tip, left mouth corner, right mouth corner.
  static const List<List<double>> _canonicalTemplate = [
    [38.2946, 51.6963],
    [73.5318, 51.5014],
    [56.0252, 71.7366],
    [41.5493, 92.3655],
    [70.7299, 92.2041],
  ];

  /// The ML Kit landmarks that correspond, in order, to `_canonicalTemplate`.
  static const List<FaceLandmarkType> _alignmentLandmarks = [
    FaceLandmarkType.leftEye,
    FaceLandmarkType.rightEye,
    FaceLandmarkType.noseBase,
    FaceLandmarkType.leftMouth,
    FaceLandmarkType.rightMouth,
  ];

  /// Align the detected face onto the canonical template and return a 112×112
  /// crop, or null when the landmarks are missing or the transform is degenerate.
  ///
  /// This is the single biggest free accuracy lever: an aligned crop removes the
  /// pose/scale variance a raw bounding box leaves in the embedding, so the same
  /// person's vectors cluster and different people's spread apart.
  img.Image? _alignFace(img.Image image, Face face) {
    // The canonical template is defined for a 112×112 crop; a model with a
    // different input falls back to the padded bounding-box crop.
    if (_inputSize != 112) return null;

    final source = <List<double>>[];
    for (final type in _alignmentLandmarks) {
      final position = face.landmarks[type]?.position;
      if (position == null) return null;
      source.add([position.x.toDouble(), position.y.toDouble()]);
    }

    final transform = _similarityTransform(source, _canonicalTemplate);
    if (transform == null) return null;

    return _warpToInput(image, transform);
  }

  /// Closed-form least-squares similarity transform (uniform scale + rotation +
  /// translation, no shear/reflection) mapping [source] onto [target].
  ///
  /// Returns `[scale·cosθ, scale·sinθ, tx, ty]`, or null for a degenerate frame.
  /// Public for unit testing.
  static List<double>? similarityTransform(
    List<List<double>> source,
    List<List<double>> target,
  ) {
    if (source.length != target.length || source.isEmpty) return null;

    final n = source.length;
    var meanSx = 0.0, meanSy = 0.0, meanTx = 0.0, meanTy = 0.0;
    for (final p in source) {
      meanSx += p[0];
      meanSy += p[1];
    }
    for (final p in target) {
      meanTx += p[0];
      meanTy += p[1];
    }
    meanSx /= n;
    meanSy /= n;
    meanTx /= n;
    meanTy /= n;

    var a = 0.0, b = 0.0, denom = 0.0;
    for (var i = 0; i < n; i++) {
      final px = source[i][0] - meanSx;
      final py = source[i][1] - meanSy;
      final qx = target[i][0] - meanTx;
      final qy = target[i][1] - meanTy;
      a += px * qx + py * qy;
      b += px * qy - py * qx;
      denom += px * px + py * py;
    }
    if (denom <= 1e-6) return null;

    final c = a / denom;
    final s = b / denom;
    final scale = sqrt(c * c + s * s);
    if (scale < 0.02 || scale > 40) return null;

    final tx = meanTx - (c * meanSx - s * meanSy);
    final ty = meanTy - (s * meanSx + c * meanSy);
    return [c, s, tx, ty];
  }

  static List<double>? _similarityTransform(
    List<List<double>> source,
    List<List<double>> target,
  ) =>
      similarityTransform(source, target);

  /// Warp [image] into a 112×112 crop with the forward transform
  /// `dst = [c -s; s c]·src + t`, sampling each output pixel by its inverse.
  img.Image _warpToInput(img.Image image, List<double> transform) {
    final c = transform[0];
    final s = transform[1];
    final tx = transform[2];
    final ty = transform[3];
    final det = c * c + s * s;

    final output = img.Image(width: _inputSize, height: _inputSize);
    for (var y = 0; y < _inputSize; y++) {
      for (var x = 0; x < _inputSize; x++) {
        final dx = x - tx;
        final dy = y - ty;
        // Inverse of the similarity transform (rotate by -θ, then un-scale).
        final sx = (c * dx + s * dy) / det;
        final sy = (-s * dx + c * dy) / det;
        final pixel = _bilinearSample(image, sx, sy);
        output.setPixelRgb(x, y, pixel[0], pixel[1], pixel[2]);
      }
    }
    return output;
  }

  /// Bilinear sample; black outside the source image. Public for unit testing.
  static List<int> bilinearSample(img.Image image, double x, double y) =>
      _bilinearSample(image, x, y);

  static List<int> _bilinearSample(img.Image image, double x, double y) {
    if (x < 0 || y < 0 || x > image.width - 1 || y > image.height - 1) {
      return const [0, 0, 0];
    }
    final x0 = x.floor();
    final y0 = y.floor();
    final x1 = (x0 + 1 < image.width) ? x0 + 1 : x0;
    final y1 = (y0 + 1 < image.height) ? y0 + 1 : y0;
    final fx = x - x0;
    final fy = y - y0;

    final p00 = image.getPixel(x0, y0);
    final p10 = image.getPixel(x1, y0);
    final p01 = image.getPixel(x0, y1);
    final p11 = image.getPixel(x1, y1);

    int mix(num a, num b, num cc, num d) {
      final top = a * (1 - fx) + b * fx;
      final bottom = cc * (1 - fx) + d * fx;
      return (top * (1 - fy) + bottom * fy).round().clamp(0, 255);
    }

    return [
      mix(p00.r, p10.r, p01.r, p11.r),
      mix(p00.g, p10.g, p01.g, p11.g),
      mix(p00.b, p10.b, p01.b, p11.b),
    ];
  }

  /// Convert image to Float32 input tensor [1, 112, 112, 3] normalized to [-1, 1]
  List<List<List<List<double>>>> _imageToFloat32List(img.Image image) {
    final result = List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (y) => List.generate(
          _inputSize,
          (x) {
            final pixel = image.getPixel(x, y);
            return [
              (pixel.r.toDouble() - 127.5) / 128.0,
              (pixel.g.toDouble() - 127.5) / 128.0,
              (pixel.b.toDouble() - 127.5) / 128.0,
            ];
          },
        ),
      ),
    );
    return result;
  }

  List<double> _embeddingFromFaceImage(img.Image faceImage) {
    final resized = img.copyResize(
      faceImage,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.cubic,
    );

    final input = _imageToFloat32List(resized);
    final output = List.filled(embeddingSize, 0.0).reshape([1, embeddingSize]);
    _interpreter!.run(input, output);
    return _l2Normalize(List<double>.from(output[0]));
  }

  List<double> _generateRobustEmbedding(img.Image croppedFace) {
    final variants = <img.Image>[croppedFace];

    variants.add(img.flipHorizontal(croppedFace.clone()));

    final gray = img.grayscale(croppedFace.clone());
    variants.add(gray);
    variants.add(img.flipHorizontal(gray.clone()));

    final embeddings = variants.map(_embeddingFromFaceImage).toList();
    return _averageEmbeddings(embeddings);
  }

  /// L2 normalize the embedding vector
  List<double> _l2Normalize(List<double> vector) {
    double norm = sqrt(vector.fold(0.0, (sum, v) => sum + v * v));
    if (norm == 0) return vector;
    return vector.map((v) => v / norm).toList();
  }

  /// Cosine similarity between two L2-normalized embeddings
  double _cosineSimilarity(List<double> a, List<double> b) {
    double dot = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot.clamp(-1.0, 1.0);
  }

  /// Average multiple embedding vectors
  List<double> _averageEmbeddings(List<List<double>> embeddings) {
    if (embeddings.isEmpty) return [];
    if (embeddings.length == 1) return embeddings.first;

    final avg = List.filled(embeddingSize, 0.0);
    for (final emb in embeddings) {
      for (int i = 0; i < embeddingSize; i++) {
        avg[i] += emb[i];
      }
    }
    for (int i = 0; i < embeddingSize; i++) {
      avg[i] /= embeddings.length;
    }
    return _l2Normalize(avg);
  }

  // ---- Registration & Matching ----

  /// Register a single face capture with same-person and front-camera checks.
  Future<FaceRegistrationResult> registerFaceCapture(
    File imageFile, {
    int captureNumber = 1,
    FaceAngle? targetAngle,
  }) async {
    // Generate embedding with quality + front camera checks (no smile required for registration)
    final angled = targetAngle != null && targetAngle != FaceAngle.straight;
    final result = await generateEmbedding(
      imageFile,
      checkQuality: true,
      checkFrontCam: true,
      requireFrontCamCentering: true,
      frontCamCenterTolerance:
          angled ? stillAngledCenterTolerance : stillCenterTolerance,
      skipRotationCheck: angled,
    );

    if (result.embedding == null) {
      return FaceRegistrationResult(
        success: false,
        message: result.error ?? 'No face detected. Please try again.',
        quality: result.quality,
        captureNumber: captureNumber,
        totalCaptures: registrationCaptures,
      );
    }

    final embeddings = captureNumber > 1
        ? _registeredEmbeddings.map((item) => List<double>.from(item)).toList()
        : <List<double>>[];

    // Same-person check: verify this capture is the same person as previous captures.
    //
    // This anchors to the AVERAGE of the captures already taken, not the
    // best-matching one. A different person can resemble a single pose yet will
    // not match the person's mean face — so this is what stops a shared account
    // from quietly enrolling several people into one template set, the root
    // cause of "one face, many identities" on a shared test account.
    if (embeddings.isNotEmpty) {
      final requiredSimilarity = _requiredSamePersonThreshold(targetAngle);
      final avgSimilarity = _cosineSimilarity(
        result.embedding!,
        _averageEmbeddings(embeddings),
      );

      if (avgSimilarity < requiredSimilarity) {
        return FaceRegistrationResult(
          success: false,
          message:
              'Different person detected (${(avgSimilarity * 100).toStringAsFixed(1)}% match to the face already being registered, required ${(requiredSimilarity * 100).toStringAsFixed(0)}%). Please retake this capture with similar distance and lighting.',
          quality: result.quality,
          captureNumber: captureNumber,
          totalCaptures: registrationCaptures,
          isDifferentPerson: true,
        );
      }
    }

    embeddings.add(result.embedding!);
    _registeredEmbeddings = embeddings;

    // If final capture, compute and store average embedding
    if (captureNumber >= registrationCaptures) {
      final avgEmbedding = _averageEmbeddings(embeddings);
      _registeredAvgEmbedding = avgEmbedding;
      _adaptiveEmbeddings = <List<double>>[];
      _registrationTime = DateTime.now().toIso8601String();
      _registrationCaptureCount = embeddings.length;

      return FaceRegistrationResult(
        success: true,
        message: 'Face registered with ${embeddings.length} captures! Maximum accuracy enabled.',
        quality: result.quality,
        captureNumber: captureNumber,
        totalCaptures: registrationCaptures,
      );
    }

    return FaceRegistrationResult(
      success: true,
      message: 'Capture $captureNumber of $registrationCaptures saved. ${registrationCaptures - captureNumber} more needed.',
      quality: result.quality,
      captureNumber: captureNumber,
      totalCaptures: registrationCaptures,
      isPartial: true,
    );
  }

  /// Legacy single-image registration
  Future<FaceRegistrationResult> registerFace(File imageFile) async {
    final result = await generateEmbedding(imageFile, checkQuality: true, checkFrontCam: true);
    if (result.embedding == null) {
      return FaceRegistrationResult(
        success: false,
        message: result.error ?? 'No face detected in the image. Please try again with a clear selfie.',
        quality: result.quality,
      );
    }

    _registeredAvgEmbedding = List<double>.from(result.embedding!);
    _registeredEmbeddings = [List<double>.from(result.embedding!)];
    _adaptiveEmbeddings = <List<double>>[];
    _registrationTime = DateTime.now().toIso8601String();
    _registrationCaptureCount = 1;

    return FaceRegistrationResult(
      success: true,
      message: 'Face registered successfully!',
      quality: result.quality,
    );
  }

  /// Check if a valid face template is loaded in memory.
  Future<bool> isFaceRegistered() async {
    return FaceRegistrationData.isValidEmbedding(_registeredAvgEmbedding, expectedSize: null);
  }

  /// Get the registration timestamp
  Future<String?> getRegistrationTime() async {
    return _registrationTime;
  }

  /// Get the number of captures used during registration
  Future<int> getRegistrationCaptureCount() async {
    return _registrationCaptureCount;
  }

  /// Delete the registered face
  Future<void> deleteRegisteredFace() async {
    clearRegistrationMemory();
  }

  /// Verify a face against registration templates with strict core consistency.
  ///
  /// Runs a SINGLE inference by default: the 4-variant average inflates
  /// cross-identity similarity (it pulls everyone toward the mean) and costs 4×
  /// the time, so it is kept for enrolment only. Adaptive templates are reported
  /// but never decide identity.
  Future<FaceVerificationResult> verifyFace(
    File imageFile, {
    bool requireSmile = false,
    bool robustEmbedding = false,
  }) async {
    final storedEmbedding = _registeredAvgEmbedding;

    if (storedEmbedding == null || storedEmbedding.isEmpty) {
      return FaceVerificationResult(
        isMatch: false,
        confidence: 0,
        message: 'Your face data is missing or unreadable. Please register your face again.',
      );
    }

    // Generate embedding with quality, liveness, and front camera checks
    final result = await generateEmbedding(
      imageFile,
      checkQuality: true,
      checkLivenessSmile: requireSmile,
      checkFrontCam: true,
      robustEmbedding: robustEmbedding,
    );
    if (result.embedding == null) {
      return FaceVerificationResult(
        isMatch: false,
        confidence: 0,
        message: result.error ?? 'No face detected. Please take a clear selfie.',
        quality: result.quality,
      );
    }

    // A stored template from a different model has a different vector length and
    // would make cosine similarity throw. Treat the mismatch as out-of-date so
    // the officer re-registers rather than hitting a crash.
    final probeLength = result.embedding!.length;
    if (storedEmbedding.length != probeLength ||
        _registeredEmbeddings.any((e) => e.length != probeLength)) {
      return FaceVerificationResult(
        isMatch: false,
        confidence: 0,
        message:
            'Your face template is out of date. Please register your face again.',
        quality: result.quality,
      );
    }

    // Core similarities (average + all registration captures)
    final coreSimilarityScores = <double>[
      _cosineSimilarity(result.embedding!, storedEmbedding),
    ];

    // Compare with all registration captures (core templates)
    for (final emb in _registeredEmbeddings) {
      coreSimilarityScores.add(_cosineSimilarity(result.embedding!, emb));
    }

    // Adaptive similarities (supporting templates only). A stale adaptive vector
    // from another model is skipped rather than crashing the cosine.
    final adaptiveSimilarityScores = <double>[];
    for (final emb in _adaptiveEmbeddings) {
      if (emb.length != probeLength) continue;
      adaptiveSimilarityScores.add(_cosineSimilarity(result.embedding!, emb));
    }

    // Core weighted top-k aggregation (identity decision is core-template driven)
    final coreSorted = [...coreSimilarityScores]..sort((a, b) => b.compareTo(a));
    final coreTop1 = coreSorted.isNotEmpty ? coreSorted[0] : 0.0;
    final coreTop2 = coreSorted.length > 1 ? coreSorted[1] : coreTop1;
    final coreTop3 = coreSorted.length > 2 ? coreSorted[2] : coreTop2;
    final coreAggregateSimilarity =
        (coreTop1 * 0.60) + (coreTop2 * 0.25) + (coreTop3 * 0.15);
    final finalSimilarity = max(coreTop1, coreAggregateSimilarity);

    final adaptiveSorted = [...adaptiveSimilarityScores]
      ..sort((a, b) => b.compareTo(a));
    final adaptiveTop1 = adaptiveSorted.isNotEmpty ? adaptiveSorted[0] : 0.0;

    final qualityScore = result.quality?.score ?? 100.0;
    final qualityAwareThreshold =
        qualityScore >= 75 ? _matchThreshold : _matchThreshold + 0.02;
    final coreConsistencyThreshold = qualityAwareThreshold - 0.02;
    // Require agreement across the enrolled templates when there are enough of
    // them; a single template (the average only) cannot satisfy a two-hit rule.
    final requiredCoreHits = coreSimilarityScores.length >= _requiredCoreHits
        ? _requiredCoreHits
        : 1;
    final coreHitCount = coreSimilarityScores
        .where((sim) => sim >= coreConsistencyThreshold)
        .length;

    final strongCoreMatch =
        coreTop1 >= _strongMatchThreshold && coreTop2 >= coreConsistencyThreshold;

    final isCoreMatch = coreTop1 >= qualityAwareThreshold &&
        coreAggregateSimilarity >= coreConsistencyThreshold &&
        coreHitCount >= requiredCoreHits;

    final isMatch = isCoreMatch || strongCoreMatch;
    final finalConfidence = (finalSimilarity * 100).clamp(0.0, 100.0);

    // Adaptive templates are no longer auto-enrolled: on a shared account they
    // accumulated other people's faces. Adaptive similarity is reported for
    // context only, never used for the identity decision.
    final supportiveAdaptive = adaptiveTop1 >= coreConsistencyThreshold;

    return FaceVerificationResult(
      isMatch: isMatch,
      confidence: finalConfidence,
      quality: result.quality,
      message: isMatch
          ? 'Face verified! (${finalConfidence.toStringAsFixed(1)}% match)'
          : 'Face match too low: ${finalConfidence.toStringAsFixed(1)}%. Need stable core match ≥ ${(qualityAwareThreshold * 100).toStringAsFixed(0)}% (adaptive ${(supportiveAdaptive ? 'supporting' : 'not supporting')}). Please try again in good lighting, facing the camera directly.',
    );
  }

  /// Release resources
  void dispose() {
    if (_isInitialized) {
      _liveFaceDetector.close();
      _finalFaceDetector.close();
    }
    _interpreter?.close();
    _isInitialized = false;
  }
}

// ---- Result classes ----

class LivenessResult {
  final bool isLive;
  final List<String> issues;
  final double smileProbability;
  final double sharpnessScore;

  LivenessResult({
    required this.isLive,
    required this.issues,
    required this.smileProbability,
    required this.sharpnessScore,
  });
}

class FrontCameraCheckResult {
  final bool isFrontCamera;
  final double faceRatio;
  final String? issue;

  FrontCameraCheckResult({
    required this.isFrontCamera,
    required this.faceRatio,
    this.issue,
  });
}

class FaceQualityResult {
  final double score;
  final List<String> issues;
  final bool isAcceptable;
  final double faceRatio;
  final double yaw;
  final double pitch;

  FaceQualityResult({
    required this.score,
    required this.issues,
    required this.isAcceptable,
    required this.faceRatio,
    required this.yaw,
    required this.pitch,
  });
}

class EmbeddingResult {
  final List<double>? embedding;
  final FaceQualityResult? quality;
  final String? error;

  EmbeddingResult({required this.embedding, required this.quality, required this.error});
}

class FaceRegistrationResult {
  final bool success;
  final String message;
  final FaceQualityResult? quality;
  final int captureNumber;
  final int totalCaptures;
  final bool isPartial;
  final bool isDifferentPerson;

  FaceRegistrationResult({
    required this.success,
    required this.message,
    this.quality,
    this.captureNumber = 1,
    this.totalCaptures = 1,
    this.isPartial = false,
    this.isDifferentPerson = false,
  });
}

class FaceVerificationResult {
  final bool isMatch;
  final double confidence;
  final String message;
  final FaceQualityResult? quality;

  FaceVerificationResult({
    required this.isMatch,
    required this.confidence,
    required this.message,
    this.quality,
  });
}
