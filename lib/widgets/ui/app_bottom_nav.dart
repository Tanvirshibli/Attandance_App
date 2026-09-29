import 'package:flutter/material.dart';

import '../../config/app_design.dart';
import 'app_icon_tile.dart';

/// The bottom navigation bar.
///
/// The selected tab shows its label; the others stay icon-only, which is what
/// keeps five destinations legible on a narrow phone. Every item keeps a 48dp
/// hit area.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<AppNavItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpace.xs,
        0,
        AppSpace.xs,
        AppSpace.sm,
      ),
      padding: const EdgeInsets.all(AppSpace.xxs),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadows.raised,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var i = 0; i < items.length; i++)
            _NavButton(
              item: items[i],
              selected: i == currentIndex,
              onTap: () => onTap(i),
            ),
        ],
      ),
    );
  }
}

class AppNavItem {
  const AppNavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Color color;
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final AppNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 48),
          padding: EdgeInsets.symmetric(
            horizontal: selected ? AppSpace.sm : AppSpace.xs,
            vertical: AppSpace.xs,
          ),
          decoration: BoxDecoration(
            color: selected
                ? item.color.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                selected ? item.activeIcon : item.icon,
                size: 23,
                color: selected ? item.color : AppColors.inkFaint,
                secondaryOpacity: 0.4,
                secondaryColor: selected ? item.color : AppColors.inkFaint,
              ),
              if (selected) ...[
                const SizedBox(width: AppSpace.xxs + 2),
                Text(
                  item.label,
                  style: AppType.micro.copyWith(
                    color: item.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
