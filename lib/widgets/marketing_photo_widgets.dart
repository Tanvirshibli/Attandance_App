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
    final photos = attachments
        .where((a) => a.displayUrl != null && a.displayUrl!.isNotEmpty)
        .toList();
    if (photos.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
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
            children: photos.map((attachment) {
              final url = attachment.displayUrl!;
              return GestureDetector(
                onTap: () => openMarketingPhotoViewer(context, url),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 120,
                    height: 120,
                    child: CachedNetworkImage(
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
                    ),
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
