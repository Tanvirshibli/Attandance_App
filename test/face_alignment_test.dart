import 'dart:math';

import 'package:employee_attendance/services/face_recognition_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('face landmark alignment', () {
    test('identical source and target give an identity transform', () {
      final points = [
        [10.0, 20.0],
        [40.0, 20.0],
        [25.0, 45.0],
        [15.0, 60.0],
        [35.0, 60.0],
      ];

      final t = FaceRecognitionService.similarityTransform(points, points)!;

      expect(t[0], closeTo(1.0, 1e-9)); // scale * cos(theta)
      expect(t[1], closeTo(0.0, 1e-9)); // scale * sin(theta)
      expect(t[2], closeTo(0.0, 1e-6)); // tx
      expect(t[3], closeTo(0.0, 1e-6)); // ty
    });

    test('a known scale and rotation are recovered from the point pairs', () {
      final src = [
        [0.0, 0.0],
        [10.0, 0.0],
        [5.0, 5.0],
        [2.0, 9.0],
        [8.0, 9.0],
      ];
      const scale = 2.0;
      final theta = pi / 6;
      final c = scale * cos(theta);
      final s = scale * sin(theta);
      const tx = 3.0;
      const ty = -4.0;

      final dst = src
          .map((p) => [c * p[0] - s * p[1] + tx, s * p[0] + c * p[1] + ty])
          .toList();

      final t = FaceRecognitionService.similarityTransform(src, dst)!;

      expect(t[0], closeTo(c, 1e-6));
      expect(t[1], closeTo(s, 1e-6));
      expect(t[2], closeTo(tx, 1e-4));
      expect(t[3], closeTo(ty, 1e-4));
    });

    test('a degenerate (all-equal) source returns null so the caller falls back',
        () {
      final src = List.generate(5, (_) => [5.0, 5.0]);
      expect(FaceRecognitionService.similarityTransform(src, src), isNull);
    });

    test('mismatched point counts return null', () {
      expect(
        FaceRecognitionService.similarityTransform(
          [
            [0.0, 0.0],
            [1.0, 1.0],
          ],
          [
            [0.0, 0.0],
            [1.0, 1.0],
            [2.0, 2.0],
          ],
        ),
        isNull,
      );
    });

    test('bilinear sampling is black outside the source image', () {
      final image = img.Image(width: 4, height: 4);
      expect(FaceRecognitionService.bilinearSample(image, -1, 1), [0, 0, 0]);
      expect(FaceRecognitionService.bilinearSample(image, 10, 1), [0, 0, 0]);
    });
  });
}
