import 'dart:math' as math;

import 'package:employee_attendance/models/face_registration_data.dart';
import 'package:employee_attendance/services/face_recognition_service.dart';
import 'package:employee_attendance/utils/face_guide_placement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('face ratio gates', () {
    test('0.08 is too far for live and still', () {
      expect(
        FaceRecognitionService.isFaceRatioAcceptable(
          0.08,
          forLiveGuidance: true,
        ),
        isFalse,
      );
      expect(
        FaceRecognitionService.isFaceRatioAcceptable(
          0.08,
          forLiveGuidance: false,
        ),
        isFalse,
      );
      expect(
        FaceRecognitionService.faceFramingIssue(
          0.08,
          forLiveGuidance: true,
        ),
        contains('closer'),
      );
    });

    test('0.18 passes the live size floor', () {
      expect(
        FaceRecognitionService.isFaceRatioAcceptable(
          0.18,
          forLiveGuidance: true,
        ),
        isTrue,
      );
      expect(
        FaceRecognitionService.isFaceRatioAcceptable(
          0.18,
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

  group('oval fill', () {
    const imageSize = Size(480, 640);
    const previewSize = Size(360, 396);

    test('small centered 8% face fails fill', () {
      const area = 0.08 * 480 * 640;
      final side = math.sqrt(area);
      final box = Rect.fromCenter(
        center: const Offset(240, 320),
        width: side,
        height: side,
      );
      expect(
        FaceGuidePlacement.issue(
          faceBox: box,
          imageSize: imageSize,
          previewSize: previewSize,
        ),
        contains('closer'),
      );
    });

    test('face covering about 75% of oval height passes', () {
      const ovalHeight = 396 * 0.72;
      const scale = 360 / 480;
      final imageHeight = ovalHeight * 0.75 / scale;
      final box = Rect.fromCenter(
        center: const Offset(240, 320),
        width: imageHeight * 0.72,
        height: imageHeight,
      );
      expect(
        FaceGuidePlacement.issue(
          faceBox: box,
          imageSize: imageSize,
          previewSize: previewSize,
        ),
        isNull,
      );
    });

    test('off-center large face fails center', () {
      const ovalHeight = 396 * 0.72;
      const scale = 360 / 480;
      final imageHeight = ovalHeight * 0.75 / scale;
      final box = Rect.fromLTWH(
        0,
        320 - imageHeight / 2,
        imageHeight * 0.72,
        imageHeight,
      );
      expect(
        FaceGuidePlacement.issue(
          faceBox: box,
          imageSize: imageSize,
          previewSize: previewSize,
        ),
        contains('Center'),
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
