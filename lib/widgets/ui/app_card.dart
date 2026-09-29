import 'package:flutter/material.dart';

import '../../config/app_design.dart';

/// The app's base surface.
///
/// Deliberately mirrors `SectionCard`'s parameters (`child`, `padding`,
/// `margin`) so it can stand in for it during migration without touching a
/// single call site.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.md),
    this.margin,
    this.onTap,
    this.accent,
    this.elevated = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  /// When set the whole card becomes tappable. A null value renders a plain
  /// container, so a card that is not interactive never shows a ripple.
  final VoidCallback? onTap;

  /// Tints the left edge with a module colour.
  final Color? accent;

  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.xl);
    final body = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: radius,
        border: Border.all(color: AppColors.line),
        boxShadow: elevated ? AppShadows.raised : AppShadows.card,
      ),
      child: accent == null
          ? child
          : IntrinsicHeight(
              // IntrinsicHeight is required, not incidental: a Row with
              // `CrossAxisAlignment.stretch` needs a bounded height, and inside
              // a sliver the height is unbounded. Without this the layout
              // asserts and the entire screen renders blank. This exact bug hit
              // two screens before it was found, so it is worth the cost here
              // rather than at each call site.
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 4, color: accent),
                  Expanded(child: child),
                ],
              ),
            ),
    );

    if (onTap == null) return body;

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: body,
      ),
    );
  }
}
