import 'package:flutter/material.dart';

import '../../config/app_design.dart';
import 'app_icon_tile.dart';

/// A status chip that always pairs its colour with an icon and a word, so the
/// state survives a colourblind filter and a greyscale print.
class AppStatusChip extends StatelessWidget {
  const AppStatusChip({
    super.key,
    required this.status,
    this.compact = false,
    this.color,
    this.icon,
  });

  final String? status;
  final bool compact;

  /// Overrides the automatic status colour.
  final Color? color;

  /// Overrides the automatic icon.
  final IconData? icon;

  static IconData _iconFor(String normalized) {
    switch (normalized) {
      case 'present':
      case 'active':
      case 'approved':
      case 'delivered':
      case 'completed':
        return AppIcons.check;
      case 'late':
      case 'requested':
      case 'pending':
        return AppIcons.clock;
      case 'absent':
      case 'rejected':
      case 'cancelled':
      case 'canceled':
        return AppIcons.warning;
      case 'leave':
        return AppIcons.calendar;
      case 'inactive':
      case 'archived':
        return AppIcons.clock;
      case 'draft':
        return AppIcons.note;
      default:
        return AppIcons.info;
    }
  }

  static String _label(String raw) {
    if (raw.isEmpty) return '';
    return raw[0].toUpperCase() + raw.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final raw = status?.trim() ?? '';
    if (raw.isEmpty) return const SizedBox.shrink();

    final resolved = color ?? AppColors.forStatus(raw);
    final glyph = icon ?? _iconFor(raw.toLowerCase());

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpace.xs : 10,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: resolved.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(
            glyph,
            size: compact ? 12 : 14,
            color: resolved,
            secondaryOpacity: 0.5,
          ),
          const SizedBox(width: AppSpace.xxs),
          Text(
            _label(raw),
            style: (compact ? AppType.micro : AppType.meta).copyWith(
              color: resolved,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A section heading with an accent bar, so long pages can be scanned.
class AppSectionTitle extends StatelessWidget {
  const AppSectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.accent,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Color? accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppColors.primary;
    return Row(
      // MainAxisSize.min: this widget is used inside a parent Row (for example
      // the geo "Recent pings" header) that shrink-wraps its children. With the
      // default `max`, the Expanded below asks for unbounded width and the
      // layout asserts, taking the whole screen down.
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 4,
          height: subtitle == null ? 18 : 32,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: AppType.h3.copyWith(color: AppColors.ink),
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty)
                Text(
                  subtitle!,
                  style: AppType.meta.copyWith(color: AppColors.inkMuted),
                ),
            ],
          ),
        ),
        if (trailing != null) ?trailing,
      ],
    );
  }
}
