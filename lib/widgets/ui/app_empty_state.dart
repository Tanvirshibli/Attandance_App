import 'package:flutter/material.dart';

import '../../config/app_design.dart';
import 'app_button.dart';
import 'app_icon_tile.dart';

enum AppEmptyTone { neutral, error }

/// The module's empty / error / unavailable state.
///
/// Mirrors `ApiEmptyState`'s parameters so it can replace it during migration.
/// A missing `onRetry` is a deliberate dead end, not an oversight — several
/// screens rely on that.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onRetry,
    this.comingSoon = false,
    this.tone = AppEmptyTone.neutral,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onRetry;
  final bool comingSoon;
  final AppEmptyTone tone;

  @override
  Widget build(BuildContext context) {
    final color = tone == AppEmptyTone.error
        ? AppColors.error
        : AppColors.primary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.xxl),
              ),
              child: AppIcon(
                icon,
                size: 34,
                color: color,
                secondaryOpacity: 0.4,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppType.h3.copyWith(color: AppColors.ink),
            ),
            if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpace.xs),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: AppType.bodySm.copyWith(
                  color: AppColors.inkMuted,
                  height: 1.5,
                ),
              ),
            ],
            if (comingSoon) ...[
              const SizedBox(height: AppSpace.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.sm,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  'Backend API coming soon',
                  style: AppType.micro.copyWith(color: AppColors.warning),
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: AppSpace.lg),
              SizedBox(
                width: 160,
                child: AppButton(
                  label: 'Try again',
                  icon: AppIcons.refresh,
                  onPressed: onRetry,
                  kind: AppButtonKind.secondary,
                  accent: color,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
