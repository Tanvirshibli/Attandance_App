import 'dart:math' as math;

import 'package:employee_attendance/models/face_registration_data.dart';
import 'package:employee_attendance/services/face_recognition_service.dart';
import 'package:employee_attendance/utils/face_guide_placement.dart';
import 'package:employee_attendance/widgets/face_capture_stage.dart';
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

    test('0.18 passes the live and still size floor', () {
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

  group('face guide geometry', () {
    test('guide sits under the top overlay reserve', () {
      const preview = Size(360, 396);
      final frame = faceGuideRect(preview);
      expect(frame.center.dx, closeTo(preview.width / 2, 0.01));
      expect(frame.top, greaterThanOrEqualTo(faceGuideTopReserve - 0.01));
      expect(frame.bottom, lessThanOrEqualTo(preview.height - faceGuideMargin));
    });

    test('tick origin is the center of the guide', () {
      const preview = Size(360, 396);
      final frame = faceGuideRect(preview);
      final origin = faceGuideTickOrigin(preview);
      expect(origin.dx + faceGuideTickSize / 2, closeTo(frame.center.dx, 0.01));
      expect(origin.dy + faceGuideTickSize / 2, closeTo(frame.center.dy, 0.01));
    });
  });

  group('frame fill', () {
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

    test('face covering about 75% of frame height passes', () {
      final frameHeight = faceGuideRect(previewSize).height;
      const scale = 360 / 480;
      final imageHeight = frameHeight * 0.75 / scale;
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
      final frameHeight = faceGuideRect(previewSize).height;
      const scale = 360 / 480;
      final imageHeight = frameHeight * 0.75 / scale;
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

    test('70% guide fill meets the 16% still area floor', () {
      final frame = faceGuideRect(previewSize);
      const scale = 360 / 480;
      final imageHeight =
          frame.height * (FaceGuidePlacement.minOvalHeightFill + 0.01) / scale;
      final box = Rect.fromCenter(
        center: const Offset(240, 320),
        width: imageHeight * 0.72,
        height: imageHeight,
      );
      final areaRatio = (box.width * box.height) / (imageSize.width * imageSize.height);
      expect(
        areaRatio,
        greaterThanOrEqualTo(FaceRecognitionService.minAcceptableFaceRatio),
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

    test('turned pose uses a looser center inset', () {
      final frameHeight = faceGuideRect(previewSize).height;
      const scale = 360 / 480;
      final imageHeight = frameHeight * 0.75 / scale;
      final tight = FaceGuidePlacement.insetGuideRect(previewSize);
      final mappedX = tight.left - 8;
      final imageX = mappedX / scale;
      final box = Rect.fromCenter(
        center: Offset(imageX, 320),
        width: imageHeight * 0.72,
        height: imageHeight,
      );
      expect(
        FaceGuidePlacement.issue(
          faceBox: box,
          imageSize: imageSize,
          previewSize: previewSize,
        ),
        contains('Center'),
      );
      expect(
        FaceGuidePlacement.issue(
          faceBox: box,
          imageSize: imageSize,
          previewSize: previewSize,
          angled: true,
        ),
        isNull,
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
