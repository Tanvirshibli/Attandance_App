import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';

import '../widgets/ui/ui.dart';

/// The Alerts tab.
///
/// The app has no notifications API yet, so this is an honest empty state
/// rather than a broken list. It explains what will land here and why, rather
/// than just saying "nothing here".
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: AppHeader(
              title: 'Alerts',
              subtitle: 'What needs your attention',
              showBack: false,
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: FadeInUp(
              delay: const Duration(milliseconds: 120),
              duration: const Duration(milliseconds: 400),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg,
                  AppSpace.xl,
                  AppSpace.lg,
                  AppSpace.fabClearance,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        gradient: AppDecorations.gradientFor(AppColors.primary),
                        borderRadius: BorderRadius.circular(AppRadius.xxl + 4),
                        boxShadow: AppShadows.raised,
                      ),
                      alignment: Alignment.center,
                      child: const PhosphorIcon(
                        PhosphorIconsDuotone.bellRinging,
                        size: 44,
                        color: Colors.white,
                        duotoneSecondaryColor: Colors.white70,
                        duotoneSecondaryOpacity: 0.5,
                      ),
                    ),
                    const SizedBox(height: AppSpace.lg),
                    Text(
                      'You are all caught up',
                      style: AppType.h2.copyWith(color: AppColors.ink),
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      'Leave approvals, payment updates and face '
                      'registration reminders will appear here.',
                      textAlign: TextAlign.center,
                      style: AppType.bodySm.copyWith(
                        color: AppColors.inkMuted,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: AppSpace.xl),
                    Container(
                      padding: const EdgeInsets.all(AppSpace.md),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Column(
                        children: [
                          _ComingSoonRow(
                            icon: PhosphorIconsDuotone.calendarCheck,
                            color: AppColors.mLeave,
                            label: 'Leave requests',
                            detail: 'Awaiting your approval',
                          ),
                          Divider(
                            height: AppSpace.lg,
                            color: AppColors.line,
                          ),
                          _ComingSoonRow(
                            icon: PhosphorIconsDuotone.wallet,
                            color: AppColors.mPayments,
                            label: 'Payment updates',
                            detail: 'Vouchers and collections',
                          ),
                          Divider(
                            height: AppSpace.lg,
                            color: AppColors.line,
                          ),
                          _ComingSoonRow(
                            icon: PhosphorIconsDuotone.scan,
                            color: AppColors.mAttendance,
                            label: 'Face registration',
                            detail: 'Re-register before expiry',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComingSoonRow extends StatelessWidget {
  const _ComingSoonRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.detail,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppIconTile(icon: icon, color: color, size: AppIconTileSize.small),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppType.h3.copyWith(color: AppColors.ink),
              ),
              Text(
                detail,
                style: AppType.meta.copyWith(color: AppColors.inkFaint),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.xs,
            vertical: 3,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceSunk,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            'Soon',
            style: AppType.micro.copyWith(color: AppColors.inkFaint),
          ),
        ),
      ],
    );
  }
}
