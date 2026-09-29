import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../config/app_design.dart';

/// The screen header.
///
/// Takes the same parameters as `GradientScreenHeader` — `title`, `subtitle`,
/// `showBack`, `trailing` — so migration is a drop-in swap, and it keeps the
/// same back behaviour (`Navigator.maybePop`).
class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showBack = true,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final bool showBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        AppSpace.gutter,
        showBack
            ? MediaQuery.of(context).padding.top + AppSpace.sm
            : MediaQuery.of(context).padding.top + AppSpace.md,
        AppSpace.gutter,
        AppSpace.md,
      ),
      decoration: const BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(AppRadius.xxl),
          bottomRight: Radius.circular(AppRadius.xxl),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (showBack)
                Semantics(
                  button: true,
                  label: 'Back',
                  child: InkWell(
                    onTap: () => Navigator.of(context).maybePop(),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: const SizedBox(
                      width: 44,
                      height: 44,
                      child: _BackGlyph(),
                    ),
                  ),
                ),
              if (showBack) const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Text(
                  title,
                  style: AppType.h2.copyWith(color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpace.xs),
                trailing!,
              ],
            ],
          ),
          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpace.xxs),
            Padding(
              padding: EdgeInsets.only(left: showBack ? 52 : 0),
              child: Text(
                subtitle!,
                style: AppType.meta.copyWith(
                  color: Colors.white.withValues(alpha: 0.82),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BackGlyph extends StatelessWidget {
  const _BackGlyph();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: PhosphorIcon(
        PhosphorIconsDuotone.arrowLeft,
        size: 22,
        color: Colors.white,
      ),
    );
  }
}
