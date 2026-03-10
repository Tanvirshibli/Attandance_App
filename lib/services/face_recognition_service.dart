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
  late FaceDetector _faceDetector;
  bool _isInitialized = false;

  // MobileFaceNet input: 112x112x3, output: 1x192
  static const int _inputSize = 112;
  static const int _embeddingSize = 192;

  // Core match threshold against registration templates (avg + captures)
  static const double _matchThreshold = 0.80;

  // Strong core-template match threshold
  static const double _strongMatchThreshold = 0.88;

  // Minimum confidence to auto-enroll an adaptive template
  static const double _adaptiveEnrollmentThreshold = 0.86;

  // Same-person threshold: captures during registration must be >= 65% similar
  static const double _samePersonThreshold = 0.65;

  // Relaxed threshold for extreme registration poses (up/down)
  static const double _samePersonExtremeAngleThreshold = 0.50;

  // Minimum smile probability for liveness "smile" challenge
  static const double _smileThreshold = 0.55;

  // Liveness: minimum face-to-image area ratio to accept (prevents back camera)
  static const double _minFaceRatioForSelfie = 0.06;

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
    if (registration == null || !registration.hasData) {
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
    if (_registeredAvgEmbedding == null || _registeredAvgEmbedding!.isEmpty) {
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

    _interpreter =
        await Interpreter.fromAsset('assets/models/mobilefacenet.tflite');

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: false,
        enableLandmarks: true,
        enableClassification: true,
        enableTracking: false,
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.25,
      ),
    );

    _isInitialized = true;
  }

  /// Detect faces in an image file. Returns list of Face objects.
  Future<List<Face>> detectFaces(File imageFile) async {
    if (!_isInitialized) await initialize();
    final inputImage = InputImage.fromFile(imageFile);
    return await _faceDetector.processImage(inputImage);
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

      if (faceRatio < _minFaceRatioForSelfie) {
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
  }) {
    final faceArea = face.boundingBox.width * face.boundingBox.height;
    final imageArea = imageWidth * imageHeight;
    final faceRatio = faceArea / imageArea;

    final faceCenterX = face.boundingBox.center.dx / imageWidth;
    final faceCenterY = face.boundingBox.center.dy / imageHeight;
    final isCentered =
        (faceCenterX - 0.5).abs() < centerTolerance &&
        (faceCenterY - 0.5).abs() < centerTolerance;

    // Front camera selfie: face ratio > 6% and optionally centered
    final isFrontCamera =
        faceRatio >= _minFaceRatioForSelfie && (!requireCentering || isCentered);

    String? issue;
    if (faceRatio < _minFaceRatioForSelfie) {
      issue = 'Face appears too small — please use the front camera and hold the phone at arm\'s length.';
    } else if (requireCentering && !isCentered) {
      issue = 'Face is not centered — please look directly at the front camera.';
    }

    return FrontCameraCheckResult(
      isFrontCamera: isFrontCamera,
      faceRatio: faceRatio,
      issue: issue,
    );
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

  double _bestSimilarityWithExisting(
    List<double> newEmbedding,
    List<List<double>> existingEmbeddings,
  ) {
    if (existingEmbeddings.isEmpty) return 1.0;

    double best = -1.0;
    for (final existing in existingEmbeddings) {
      final similarity = _cosineSimilarity(newEmbedding, existing);
      if (similarity > best) best = similarity;
    }

    final avgEmbedding = _averageEmbeddings(existingEmbeddings);
    final avgSimilarity = _cosineSimilarity(newEmbedding, avgEmbedding);

    return max(best, avgSimilarity);
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
    final yaw = face.headEulerAngleY ?? 0;
    final pitch = face.headEulerAngleX ?? 0;

    switch (target) {
      case FaceAngle.straight:
        return yaw.abs() < 14 && pitch.abs() < 14;
      case FaceAngle.left:
        return yaw > 15 && yaw < 55;
      case FaceAngle.right:
        return yaw < -15 && yaw > -55;
      case FaceAngle.up:
        return pitch > 9 && pitch < 45;
      case FaceAngle.down:
        return pitch < -6 && pitch > -70;
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
    if (!_isInitialized) await initialize();
    return await _faceDetector.processImage(inputImage);
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
  FaceQualityResult checkFaceQuality(Face face, int imageWidth, int imageHeight, {bool skipRotationCheck = false}) {
    final issues = <String>[];
    double score = 100.0;

    // 1. Face size check
    final faceArea = face.boundingBox.width * face.boundingBox.height;
    final imageArea = imageWidth * imageHeight;
    final faceRatio = faceArea / imageArea;

    if (faceRatio < 0.05) {
      issues.add('Face is too far — move closer to the camera');
      score -= 40;
    } else if (faceRatio < 0.10) {
      issues.add('Face is a bit far — move slightly closer');
      score -= 20;
    } else if (faceRatio > 0.70) {
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
      issues.add('Face is off-center — position your face in the oval guide');
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

    return FaceQualityResult(
      score: score.clamp(0.0, 100.0),
      issues: issues,
      isAcceptable: score >= 50 && issues.where((i) => i.contains('too far')).isEmpty,
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
    bool skipRotationCheck = false,
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

    // 7. Crop face region with generous padding
    final croppedFace = _cropFace(rawImage, face.boundingBox);

    // 8. Generate robust embedding across appearance variants
    final embedding = _generateRobustEmbedding(croppedFace);

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
    final output = List.filled(_embeddingSize, 0.0).reshape([1, _embeddingSize]);
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

    final avg = List.filled(_embeddingSize, 0.0);
    for (final emb in embeddings) {
      for (int i = 0; i < _embeddingSize; i++) {
        avg[i] += emb[i];
      }
    }
    for (int i = 0; i < _embeddingSize; i++) {
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
    final result = await generateEmbedding(
      imageFile,
      checkQuality: true,
      checkFrontCam: true,
      requireFrontCamCentering:
          targetAngle == null || targetAngle == FaceAngle.straight,
      skipRotationCheck: targetAngle != null && targetAngle != FaceAngle.straight,
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

    // Same-person check: verify this capture is the same person as previous captures
    if (embeddings.isNotEmpty) {
      final requiredSimilarity = _requiredSamePersonThreshold(targetAngle);
      final bestSimilarity = _bestSimilarityWithExisting(
        result.embedding!,
        embeddings,
      );

      if (bestSimilarity < requiredSimilarity) {
        return FaceRegistrationResult(
          success: false,
          message:
              'Different person detected (${(bestSimilarity * 100).toStringAsFixed(1)}% similarity, required ${(requiredSimilarity * 100).toStringAsFixed(0)}%). Please retake this capture with similar distance and lighting.',
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

  /// Check if a face has been registered
  Future<bool> isFaceRegistered() async {
    return _registeredAvgEmbedding != null && _registeredAvgEmbedding!.isNotEmpty;
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
  /// Adaptive templates are used as supporting references but cannot alone approve identity.
  Future<FaceVerificationResult> verifyFace(
    File imageFile, {
    bool requireSmile = false,
  }) async {
    final storedEmbedding = _registeredAvgEmbedding;

    if (storedEmbedding == null || storedEmbedding.isEmpty) {
      return FaceVerificationResult(
        isMatch: false,
        confidence: 0,
        message: 'No face registered. Please register your face first in Profile.',
      );
    }

    // Generate embedding with quality, liveness, and front camera checks
    final result = await generateEmbedding(
      imageFile,
      checkQuality: true,
      checkLivenessSmile: requireSmile,
      checkFrontCam: true,
    );
    if (result.embedding == null) {
      return FaceVerificationResult(
        isMatch: false,
        confidence: 0,
        message: result.error ?? 'No face detected. Please take a clear selfie.',
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

    // Adaptive similarities (supporting templates only)
    final adaptiveSimilarityScores = <double>[];
    for (final emb in _adaptiveEmbeddings) {
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
    final requiredCoreHits = coreSimilarityScores.length >= 3 ? 2 : 1;
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

    if (isMatch &&
        coreTop1 >= _adaptiveEnrollmentThreshold &&
        coreAggregateSimilarity >= qualityAwareThreshold) {
      await _addAdaptiveTemplate(result.embedding!);
    }

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

  Future<void> _addAdaptiveTemplate(
    List<double> embedding,
  ) async {
    final adaptiveEmbeddings = [..._adaptiveEmbeddings];

    final exists = adaptiveEmbeddings
        .any((stored) => _cosineSimilarity(stored, embedding) > 0.97);
    if (exists) return;

    adaptiveEmbeddings.add(embedding);
    if (adaptiveEmbeddings.length > 20) {
      adaptiveEmbeddings.removeRange(0, adaptiveEmbeddings.length - 20);
    }

    _adaptiveEmbeddings = adaptiveEmbeddings;
  }

  /// Release resources
  void dispose() {
    _faceDetector.close();
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
