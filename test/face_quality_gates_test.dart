import 'package:employee_attendance/models/face_registration_data.dart';
import 'package:employee_attendance/services/face_recognition_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('face ratio gates', () {
    test('0.04 is too far for live and still', () {
      expect(
        FaceRecognitionService.isFaceRatioAcceptable(
          0.04,
          forLiveGuidance: true,
        ),
        isFalse,
      );
      expect(
        FaceRecognitionService.isFaceRatioAcceptable(
          0.04,
          forLiveGuidance: false,
        ),
        isFalse,
      );
      expect(
        FaceRecognitionService.faceFramingIssue(
          0.04,
          forLiveGuidance: true,
        ),
        contains('closer'),
      );
    });

    test('0.09 passes the live size floor', () {
      expect(
        FaceRecognitionService.isFaceRatioAcceptable(
          0.09,
          forLiveGuidance: true,
        ),
        isTrue,
      );
      expect(
        FaceRecognitionService.isFaceRatioAcceptable(
          0.09,
          forLiveGuidance: false,
        ),
        isTrue,
      );
    });

    test('too-close live faces are rejected', () {
      expect(
        FaceRecognitionService.isFaceRatioAcceptable(
          0.70,
          forLiveGuidance: true,
        ),
        isFalse,
      );
      expect(
        FaceRecognitionService.faceFramingIssue(
          0.70,
          forLiveGuidance: true,
        ),
        contains('too close'),
      );
    });
  });

  group('embedding validity', () {
    test('rejects empty, short, and non-finite vectors', () {
      expect(FaceRegistrationData.isValidEmbedding(const []), isFalse);
      expect(
        FaceRegistrationData.isValidEmbedding(List<double>.filled(8, 0.1)),
        isFalse,
      );
      final nan = List<double>.filled(192, 0.1)..[3] = double.nan;
      expect(FaceRegistrationData.isValidEmbedding(nan), isFalse);
    });

    test('accepts a 192-dim finite embedding', () {
      expect(
        FaceRegistrationData.isValidEmbedding(List<double>.filled(192, 0.02)),
        isTrue,
      );
    });

    test('fromJson rejects corrupt avg embeddings', () {
      expect(
        FaceRegistrationData.fromJson({
          'avgEmbedding': [0.1, 0.2],
          'captureEmbeddings': const [],
          'adaptiveEmbeddings': const [],
          'captureCount': 1,
        }),
        isNull,
      );
      expect(
        FaceRegistrationData.fromJson({
          'avgEmbedding': List<double>.filled(192, 0.01),
          'captureEmbeddings': const [],
          'adaptiveEmbeddings': const [],
          'captureCount': 5,
        }),
        isNotNull,
      );
    });
  });
}
