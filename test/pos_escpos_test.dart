import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:employee_attendance/services/esc_pos_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Uint8List samplePng({int width = 120, int height = 40}) {
    final image = img.Image(width: width, height: height, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(255, 255, 255, 255));
    img.drawRect(
      image,
      x1: 4,
      y1: 4,
      x2: width - 4,
      y2: height - 4,
      color: img.ColorRgba8(0, 0, 0, 255),
    );
    return Uint8List.fromList(img.encodePng(image));
  }

  int indexOfSequence(List<int> data, List<int> sequence) {
    for (var i = 0; i <= data.length - sequence.length; i++) {
      var matches = true;
      for (var j = 0; j < sequence.length; j++) {
        if (data[i + j] != sequence[j]) {
          matches = false;
          break;
        }
      }
      if (matches) return i;
    }
    return -1;
  }

  test('rasterises the receipt at the requested printer width', () async {
    final image = samplePng();

    for (final dots in [384, 576]) {
      final commands =
          await buildPngReceiptCommands(image, dotsPerLine: dots, cut: false);

      expect(commands.first, 27, reason: 'ESC init byte');
      expect(commands[1], 64, reason: 'ESC @ reset');

      final rasterIndex = indexOfSequence(commands, [29, 118, 48, 0]);
      expect(rasterIndex, isNot(-1), reason: 'GS v 0 raster header present');

      final widthBytes = dots ~/ 8;
      expect(commands[rasterIndex + 4], widthBytes & 0xFF);
      expect(commands[rasterIndex + 5], (widthBytes >> 8) & 0xFF);
    }
  });

  test('adds a feed and partial cut when requested', () async {
    final image = samplePng();

    final withoutCut =
        await buildPngReceiptCommands(image, dotsPerLine: 576, cut: false);
    final withCut = await buildPngReceiptCommands(
      image,
      dotsPerLine: 576,
      cut: true,
    );

    expect(withCut.length, greaterThan(withoutCut.length));
    expect(withCut.sublist(withCut.length - 3), [29, 86, 49]);
  });

  test('test page is a valid ESC/POS stream', () async {
    final commands = await buildTestPageCommands();

    expect(commands.first, 27);
    expect(commands[1], 64);
    expect(indexOfSequence(commands, [29, 86, 49]), isNot(-1));
  });
}
