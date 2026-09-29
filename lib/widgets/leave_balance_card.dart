import 'package:flutter/material.dart';

import '../models/leave_balance.dart';
import 'ui/ui.dart';

class LeaveBalanceCard extends StatelessWidget {
  const LeaveBalanceCard({
    super.key,
    required this.balance,
  });

  final LeaveBalance balance;

  /// Share of the entitlement already consumed — `used / earned`, not the
  /// remaining balance. Guards zero, negative and over-consumed values.
  double get _usageRatio {
    if (balance.earned <= 0) return 0;
    final ratio = balance.used / balance.earned;
    if (ratio.isNaN || ratio.isInfinite) return 0;
    return ratio.clamp(0.0, 1.0);
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final metaParts = <String>[
      if (balance.code != null && balance.code!.isNotEmpty) balance.code!,
      if (balance.year != null) '${balance.year}',
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIconTile(
                icon: AppIcons.leave,
                color: AppColors.mLeave,
                size: AppIconTileSize.small,
                semanticLabel: balance.leaveTypeName,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      balance.leaveTypeName,
                      style: AppType.h3.copyWith(color: AppColors.ink),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (metaParts.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        metaParts.join(' · '),
                        style:
                            AppType.micro.copyWith(color: AppColors.inkFaint),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.xs),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _fmt(balance.balance),
                    style: AppType.numeric.copyWith(color: AppColors.mLeave),
                  ),
                  Text(
                    'left',
                    style:
                        AppType.micro.copyWith(color: AppColors.inkFaint),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _usageRatio,
              minHeight: 4,
              backgroundColor: AppColors.mLeave.withValues(alpha: 0.10),
              valueColor: const AlwaysStoppedAnimation(AppColors.mLeave),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Row(
            children: [
              // The third column appears only when adjusted is non-zero, which
              // also changes how wide these two become. Existing behaviour,
              // deliberately preserved.
              Expanded(child: _metric('Earned', _fmt(balance.earned))),
              Expanded(child: _metric('Used', _fmt(balance.used))),
              if (balance.adjusted != null && balance.adjusted != 0)
                Expanded(child: _metric('Adjusted', _fmt(balance.adjusted!))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppType.micro.copyWith(color: AppColors.inkFaint)),
        Text(value, style: AppType.h3.copyWith(color: AppColors.ink)),
      ],
    );
  }
}
