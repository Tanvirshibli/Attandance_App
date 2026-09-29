import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../config/app_design.dart';

enum AppButtonKind { primary, secondary, ghost, danger }

/// The app's button.
///
/// Every variant clears 48dp of height and wraps a 48dp-wide hit area, so the
/// 44dp minimum touch target holds even when the icon is small.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.kind = AppButtonKind.primary,
    this.accent,
    this.expand = true,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonKind kind;

  /// Overrides the brand colour for a secondary action that belongs to a
  /// specific module.
  final Color? accent;

  /// When false the button hugs its content instead of filling the row.
  final bool expand;

  final bool busy;

  @override
  Widget build(BuildContext context) {
    final base = accent ?? AppColors.primary;
    final enabled = onPressed != null && !busy;

    final (Color background, Color foreground, Color? border) = switch (kind) {
      AppButtonKind.primary => (base, Colors.white, null),
      AppButtonKind.secondary => (AppColors.surface, base, base),
      AppButtonKind.ghost => (Colors.transparent, base, null),
      AppButtonKind.danger => (AppColors.error, Colors.white, null),
    };

    final child = busy
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(foreground),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                _icon(icon!, foreground),
                const SizedBox(width: AppSpace.xs),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyStrong.copyWith(color: foreground),
                ),
              ),
            ],
          );

    final button = Material(
      color: enabled ? background : background.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(AppRadius.md + 2),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(AppRadius.md + 2),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md + 2),
            border: border == null
                ? null
                : Border.all(
                    color: enabled ? border : border.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
          ),
          child: child,
        ),
      ),
    );

    if (!expand) return button;
    return SizedBox(width: double.infinity, child: button);
  }

  Widget _icon(IconData icon, Color color) {
    final data = icon is PhosphorDuotoneIconData
        ? PhosphorIcon(
            icon,
            size: 20,
            color: color,
            duotoneSecondaryOpacity: 0.5,
            duotoneSecondaryColor: color,
          )
        : Icon(icon, size: 20, color: color);
    return data;
  }
}
