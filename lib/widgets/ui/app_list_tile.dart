import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../config/app_design.dart';
import 'app_icon_tile.dart';

/// Icon + two lines + chevron. The workhorse row for every hub and list screen.
class AppListTile extends StatelessWidget {
  const AppListTile({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.badge,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg + 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg + 4),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.sm + 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg + 4),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              AppIconTile(
                icon: icon,
                color: color,
                badge: badge,
                semanticLabel: title,
              ),
              const SizedBox(width: AppSpace.sm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppType.h3.copyWith(color: AppColors.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: AppType.meta
                            .copyWith(color: AppColors.inkMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.xs),
              if (trailing != null)
                ?trailing
              else
                _ChevronGlyph(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChevronGlyph extends StatelessWidget {
  const _ChevronGlyph();

  @override
  Widget build(BuildContext context) {
    return const PhosphorIcon(
      PhosphorIconsDuotone.caretRight,
      size: 18,
      color: AppColors.inkFaint,
    );
  }
}
