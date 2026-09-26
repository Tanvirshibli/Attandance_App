import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Universal image upload pipeline.
///
/// Every photo the app uploads is first re-encoded to compressed WebP, then
/// sent inside a parent `image` parameter:
///   * single image  -> multipart file field `image`
///   * multiple      -> multipart file field `image[]`
///
/// Backends still convert to WebP server-side as a safety net, but the bytes
/// leaving the device are already WebP so uploads stay small.
class ImageUploadService {
  ImageUploadService._internal();
  static final ImageUploadService _instance = ImageUploadService._internal();
  factory ImageUploadService() => _instance;

  /// Largest edge of the re-encoded image.
  static const int maxDimension = 1920;

  /// WebP quality 0-100.
  static const int quality = 75;

  /// Temporary subdirectory used for converted files (cleaned per upload).
  static const String _tempDirName = 'webp_upload';

  /// Convert [source] to a compressed WebP file.
  ///
  /// Returns null only when the source cannot be decoded at all.
  Future<File?> convertToWebp(File source) async {
    try {
      final dir = await getTemporaryDirectory();
      final targetDir = Directory(p.join(dir.path, _tempDirName));
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      final target = p.join(
        targetDir.path,
        '${DateTime.now().microsecondsSinceEpoch}.webp',
      );

      final result = await FlutterImageCompress.compressAndGetFile(
        source.absolute.path,
        target,
        format: CompressFormat.webp,
        quality: quality,
        minWidth: maxDimension,
        minHeight: maxDimension,
        keepExif: false,
      );
      if (result == null) return null;
      return File(result.path);
    } catch (_) {
      return null;
    }
  }

  /// Convert an [XFile] (e.g. from image_picker) to WebP.
  Future<File?> convertXFileToWebp(XFile file) => convertToWebp(File(file.path));

  /// Convert many files; silently drops ones that fail to decode.
  Future<List<File>> convertAllToWebp(Iterable<File> sources) async {
    final out = <File>[];
    for (final source in sources) {
      final converted = await convertToWebp(source);
      if (converted != null) out.add(converted);
    }
    return out;
  }

  /// `image` multipart file for a single-image payload.
  Future<http.MultipartFile> imagePart(File webpFile) =>
      imagePartNamed('image', webpFile);

  /// Multipart file under an explicit field name (e.g. `image[2]` for
  /// index-aligned uploads where some entries have no photo).
  Future<http.MultipartFile> imagePartNamed(String name, File webpFile) {
    return http.MultipartFile.fromPath(
      name,
      webpFile.path,
      contentType: MediaType('image', 'webp'),
      filename: p.basename(webpFile.path),
    );
  }

  /// `image[]` multipart files for a multi-image payload.
  Future<List<http.MultipartFile>> imageParts(List<File> webpFiles) async {
    final parts = <http.MultipartFile>[];
    for (final file in webpFiles) {
      parts.add(
        await http.MultipartFile.fromPath(
          'image[]',
          file.path,
          contentType: MediaType('image', 'webp'),
          filename: p.basename(file.path),
        ),
      );
    }
    return parts;
  }

  /// Convert picked photos to WebP and build `image[]` parts in one call.
  Future<List<http.MultipartFile>> imagePartsFromXFiles(
    List<XFile> photos,
  ) async {
    final files = <File>[];
    for (final photo in photos) {
      final converted = await convertToWebp(File(photo.path));
      if (converted != null) files.add(converted);
    }
    return imageParts(files);
  }

  /// Remove a previously converted temp file (best-effort).
  Future<void> cleanup(File? file) async {
    if (file == null) return;
    try {
      if (file.path.contains(_tempDirName) && await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> cleanupAll(Iterable<File> files) async {
    for (final f in files) {
      await cleanup(f);
    }
  }
}
