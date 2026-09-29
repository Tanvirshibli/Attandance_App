import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../config/app_design.dart';

/// Renders any icon, including duotone, correctly.
///
/// Flutter's built-in `Icon` silently flattens a duotone glyph. Every icon in
/// the redesign goes through this so the two-tone treatment actually shows.
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size = 22,
    this.color,
    this.secondaryColor,
    this.secondaryOpacity = 0.35,
    this.semanticLabel,
  });

  final IconData icon;
  final double size;
  final Color? color;
  final Color? secondaryColor;
  final double secondaryOpacity;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? AppColors.ink;
    if (icon is PhosphorDuotoneIconData) {
      return PhosphorIcon(
        icon,
        size: size,
        color: resolved,
        semanticLabel: semanticLabel,
        duotoneSecondaryColor: secondaryColor ?? resolved,
        duotoneSecondaryOpacity: secondaryOpacity,
      );
    }
    return Icon(
      icon,
      size: size,
      color: resolved,
      semanticLabel: semanticLabel,
    );
  }
}

enum AppIconTileSize { small, medium, large }

/// A rounded, tinted or gradient-filled tile holding one icon.
///
/// This is what carries the "icon rich" character: every module, stat and list
/// row leads with one of these, and the module colour does the work of telling
/// you which area you are in.
class AppIconTile extends StatelessWidget {
  const AppIconTile({
    super.key,
    required this.icon,
    required this.color,
    this.size = AppIconTileSize.medium,
    this.filled = false,
    this.onTap,
    this.badge,
    this.semanticLabel,
  });

  final IconData icon;
  final Color color;
  final AppIconTileSize size;

  /// Gradient-filled rather than tinted. Use sparingly — for hero moments.
  final bool filled;

  final VoidCallback? onTap;

  /// A small count bubble in the corner, e.g. an unread total.
  final String? badge;

  final String? semanticLabel;

  double get _extent => switch (size) {
        AppIconTileSize.small => 40,
        AppIconTileSize.medium => 48,
        AppIconTileSize.large => 60,
      };

  @override
  Widget build(BuildContext context) {
    final extent = _extent;
    final iconSize = switch (size) {
      AppIconTileSize.small => 20.0,
      AppIconTileSize.medium => 24.0,
      AppIconTileSize.large => 30.0,
    };

    final tile = Container(
      width: extent,
      height: extent,
      decoration: BoxDecoration(
        color: filled ? null : color.withValues(alpha: 0.12),
        gradient: filled ? AppDecorations.gradientFor(color) : null,
        borderRadius: BorderRadius.circular(AppRadius.md + 2),
      ),
      alignment: Alignment.center,
      child: AppIcon(
        icon,
        size: iconSize,
        color: filled ? Colors.white : color,
        secondaryColor: filled ? Colors.white70 : color,
        secondaryOpacity: filled ? 0.45 : 0.3,
        semanticLabel: semanticLabel,
      ),
    );

    final withBadge = badge == null
        ? tile
        : Stack(
            clipBehavior: Clip.none,
            children: [
              tile,
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  constraints: const BoxConstraints(minWidth: 18),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: AppColors.surface, width: 1.5),
                  ),
                  child: Text(
                    badge!,
                    textAlign: TextAlign.center,
                    style: AppType.micro.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ],
          );

    if (onTap == null) return withBadge;

    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md + 2),
        child: withBadge,
      ),
    );
  }
}
