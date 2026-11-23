import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;

/// Builds ESC/POS command streams for the POS receipt printer.
///
/// Kept free of plugin calls so it can be unit-tested.
PaperSize posPaperSizeForDots(int dotsPerLine) =>
    dotsPerLine <= 384 ? PaperSize.mm58 : PaperSize.mm80;

/// Converts a rendered receipt PNG into a `GS v 0` raster print job.
///
/// The image is resized to [dotsPerLine] printer dots wide (384 for 58 mm,
/// 576 for 80 mm) before rasterising so print output matches the on-screen
/// preview without being cropped by the printer.
Future<List<int>> buildPngReceiptCommands(
  Uint8List pngBytes, {
  required int dotsPerLine,
  bool cut = true,
}) async {
  final decoded = img.decodeImage(pngBytes);
  if (decoded == null) {
    throw ArgumentError('The receipt image could not be decoded.');
  }

  final resized = img.copyResize(
    decoded,
    width: dotsPerLine,
    interpolation: img.Interpolation.average,
  );

  final profile = await CapabilityProfile.load();
  final generator = Generator(posPaperSizeForDots(dotsPerLine), profile);

  final bytes = <int>[];
  bytes.addAll(generator.reset());
  bytes.addAll(generator.imageRaster(resized));

  if (cut) {
    bytes.addAll(generator.feed(3));
    bytes.addAll(generator.cut(mode: PosCutMode.partial));
  }

  return bytes;
}

/// Small alignment/connection test page.
Future<List<int>> buildTestPageCommands({int dotsPerLine = 576}) async {
  final profile = await CapabilityProfile.load();
  final generator = Generator(posPaperSizeForDots(dotsPerLine), profile);

  final bytes = <int>[];
  bytes.addAll(generator.reset());
  bytes.addAll(generator.text(
    'PPHL Attendance',
    styles: const PosStyles(align: PosAlign.center, bold: true),
  ));
  bytes.addAll(generator.text(
    'POS printer connected',
    styles: const PosStyles(align: PosAlign.center),
  ));
  bytes.addAll(generator.text(
    '$dotsPerLine dots · ESC/POS',
    styles: const PosStyles(align: PosAlign.center),
  ));
  bytes.addAll(generator.feed(2));
  bytes.addAll(generator.cut(mode: PosCutMode.partial));

  return bytes;
}
