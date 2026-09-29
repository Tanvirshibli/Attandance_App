import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shimmer/shimmer.dart';

import '../../config/app_design.dart';
import 'app_icon_tile.dart';

/// A shimmering placeholder block.
///
/// Uses the `shimmer` package, which has been a dependency since the start but
/// was never wired up — every screen used to show a bare
/// `CircularProgressIndicator` instead.
class AppSkeleton extends StatelessWidget {
  const AppSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = AppRadius.sm,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceSunk,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A list of shimmering cards, so a screen that is loading keeps its shape
/// instead of collapsing to a spinner and jumping when the data lands.
class AppSkeletonList extends StatelessWidget {
  const AppSkeletonList({
    super.key,
    this.count = 4,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpace.gutter,
      AppSpace.md,
      AppSpace.gutter,
      AppSpace.xl,
    ),
  });

  final int count;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surfaceSunk,
      highlightColor: AppColors.surface,
      child: ListView.separated(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
        itemBuilder: (context, index) => Container(
          padding: const EdgeInsets.all(AppSpace.sm + 2),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg + 4),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.surfaceSunk,
                  borderRadius: BorderRadius.circular(AppRadius.md + 2),
                ),
              ),
              const SizedBox(width: AppSpace.sm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppSkeleton(width: 160),
                    const SizedBox(height: AppSpace.xs),
                    AppSkeleton(width: index.isEven ? 210 : 160, height: 11),
                    const SizedBox(height: AppSpace.xs + 2),
                    const AppSkeleton(width: 88, height: 18, radius: AppRadius.pill),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The app's inline loading indicator, for a button or a small section.
class AppLoading extends StatelessWidget {
  const AppLoading({super.key, this.label, this.onDark = false});

  final String? label;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final color = onDark ? Colors.white : AppColors.primary;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          if (label != null && label!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              label!,
              textAlign: TextAlign.center,
              style: AppType.meta.copyWith(
                color: onDark
                    ? Colors.white.withValues(alpha: 0.85)
                    : AppColors.inkMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A KPI tile for the home dashboard.
class AppStatTile extends StatelessWidget {
  const AppStatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpace.sm + 2,
        horizontal: AppSpace.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            alignment: Alignment.center,
            child: icon is PhosphorDuotoneIconData
                ? PhosphorIcon(
                    icon,
                    size: 18,
                    color: color,
                    duotoneSecondaryOpacity: 0.35,
                    duotoneSecondaryColor: color,
                  )
                : AppIcon(icon, size: 18, color: color),
          ),
          const SizedBox(height: AppSpace.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: AppType.numeric.copyWith(color: AppColors.ink),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.micro.copyWith(color: AppColors.inkFaint),
          ),
        ],
      ),
    );
  }
}
