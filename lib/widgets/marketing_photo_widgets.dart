import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../config/theme.dart';
import '../models/marketing_models.dart';

/// Local multi-image picker used on farm / dealer / market visit forms.
class MarketingPhotoPicker extends StatelessWidget {
  const MarketingPhotoPicker({
    super.key,
    required this.photos,
    required this.onPick,
    required this.onRemove,
    this.enabled = true,
  });

  final List<XFile> photos;
  final VoidCallback onPick;
  final ValueChanged<int> onRemove;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: enabled ? onPick : null,
          icon: const Icon(Icons.add_a_photo_outlined),
          label: Text(
            photos.isEmpty ? 'Add photos' : '${photos.length} photo(s) — add more',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
          ),
        ),
        if (photos.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(photos.length, (i) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      File(photos[i].path),
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (enabled)
                    Positioned(
                      top: -6,
                      right: -6,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(4),
                          minimumSize: const Size(28, 28),
                        ),
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => onRemove(i),
                      ),
                    ),
                ],
              );
            }),
          ),
        ],
      ],
    );
  }
}

/// The usable photo URLs across [attachments], first photo first.
List<String> marketingPhotoUrls(List<Attachment> attachments) => attachments
    .map((a) => a.displayUrl)
    .whereType<String>()
    .where((u) => u.isNotEmpty)
    .toList();

/// Network attachment thumbnails for detail screens.
class MarketingPhotoGrid extends StatelessWidget {
  const MarketingPhotoGrid({
    super.key,
    required this.attachments,
    this.title = 'Photos',
  });

  final List<Attachment> attachments;
  final String title;

  @override
  Widget build(BuildContext context) {
    final photos = marketingPhotoUrls(attachments);
    if (photos.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            photos.length > 1 ? '$title · ${photos.length}' : title,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: photos.map((url) {
              return GestureDetector(
                onTap: () => openMarketingPhotoViewer(context, url),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 120,
                    height: 120,
                    child: _PhotoImage(url),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

/// A compact cover thumbnail for list rows.
///
/// Renders nothing when [attachments] has no usable image, so callers can drop
/// it in unconditionally and keep their layout for photo-less records. A count
/// badge appears when there is more than one photo; a tap opens the viewer.
class MarketingThumb extends StatelessWidget {
  const MarketingThumb({
    super.key,
    required this.attachments,
    this.size = 52,
    this.radius = 14,
  });

  final List<Attachment> attachments;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final photos = marketingPhotoUrls(attachments);
    if (photos.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => openMarketingPhotoViewer(context, photos.first),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _PhotoImage(photos.first),
              if (photos.length > 1) _PhotoCountBadge(count: photos.length),
            ],
          ),
        ),
      ),
    );
  }
}

/// A full-width cover photo for grid cards; nothing when there are no photos.
class MarketingCover extends StatelessWidget {
  const MarketingCover({
    super.key,
    required this.attachments,
    this.aspectRatio = 2.4,
    this.radius = 12,
  });

  final List<Attachment> attachments;
  final double aspectRatio;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final photos = marketingPhotoUrls(attachments);
    if (photos.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => openMarketingPhotoViewer(context, photos.first),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _PhotoImage(photos.first),
              if (photos.length > 1) _PhotoCountBadge(count: photos.length),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoImage extends StatelessWidget {
  const _PhotoImage(this.url);

  final String url;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        color: AppColors.background,
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: AppColors.background,
        child: const Icon(Icons.broken_image_outlined),
      ),
    );
  }
}

class _PhotoCountBadge extends StatelessWidget {
  const _PhotoCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$count',
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

void openMarketingPhotoViewer(BuildContext context, String url) {
  showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: InteractiveViewer(
        child: AspectRatio(
          aspectRatio: 1,
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            placeholder: (context, url) => const Center(
              child: CircularProgressIndicator(),
            ),
            errorWidget: (context, url, error) =>
                const Icon(Icons.broken_image_outlined),
          ),
        ),
      ),
    ),
  );
}

/// Tap blank form chrome to dismiss keyboard / autocomplete overlays.
Widget marketingFormDismissible({required Widget child}) {
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
    child: child,
  );
}
