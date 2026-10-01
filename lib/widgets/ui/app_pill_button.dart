import 'package:flutter/material.dart';

import '../../config/app_design.dart';

/// Compact icon + label action, for rows where a full-width button would crowd
/// the space. The label is the point: it makes the action legible without a
/// tooltip or a long press, so a bare icon button is only appropriate where the
/// glyph is unambiguous on its own.
class AppPillButton extends StatelessWidget {
  const AppPillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.primary,
    this.filled = true,
    this.dense = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Module colour. A filled pill uses it as the background; a tonal one tints
  /// it into the surface.
  final Color color;

  /// Filled carries the primary action of a row, tonal the secondary beside it.
  final bool filled;

  /// Tightens the horizontal padding, for rows that already hold two pills.
  final bool dense;

  /// A disabled pill stays visible and stays tappable — [onTap] is still
  /// called, so the caller can explain *why* it is locked rather than leaving
  /// the user tapping a dead control. The appearance carries the state: the
  /// module colour drops to a muted grey and the icon becomes a lock, so the
  /// restriction is legible without a long press to discover.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final foreground = !enabled
        ? AppColors.inkMuted
        : (filled ? Colors.white : color);
    final background = !enabled
        ? AppColors.line.withValues(alpha: 0.35)
        : (filled ? color : color.withValues(alpha: 0.10));
    final shownIcon = enabled ? icon : _lockGlyph;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          // 44dp is the smallest comfortable target for a control this short.
          // Full-width buttons use 48dp because they own their whole row.
          constraints: const BoxConstraints(minHeight: 44),
          padding: EdgeInsets.symmetric(
            horizontal: dense ? AppSpace.sm : AppSpace.md,
            vertical: AppSpace.xs,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: filled
                ? null
                : Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(shownIcon, size: dense ? 16 : 18, color: foreground),
              const SizedBox(width: 6),
              // Flexible so a long label ellipsises inside whatever width the
              // pill is given. Without this the Row is sized to the text and
              // overflows by however many pixels the label is too long — which
              // is what happened to "Add dealer" / "All dealers" sharing a row
              // on a narrow handset.
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.meta.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stands in for the action's own icon while a pill is locked, so the reason
/// the control cannot be used is visible on the control itself. `Icons.lock`
/// is a Material constant — the app's `AppIcons` set has no lock glyph.
const IconData _lockGlyph = Icons.lock_outline;
