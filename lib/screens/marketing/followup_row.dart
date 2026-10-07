import 'package:flutter/material.dart';

import '../../models/marketing_models.dart';
import '../../services/marketing_service.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/voice_input_field.dart';

/// One follow-up row, shared by the hub's Follow-ups list and the
/// farm/dealer detail tabs.
class FollowupRow extends StatelessWidget {
  const FollowupRow({
    super.key,
    required this.item,
    this.onTap,
    this.showPartyName = true,
  });

  final Followup item;

  /// Set only when the follow-up can still be completed — a completed or
  /// cancelled row renders as a settled record, not as something to tap.
  final VoidCallback? onTap;

  /// Off on a party's own detail page, where the party name is the page.
  final bool showPartyName;

  static bool canComplete(String? status) {
    final s = (status ?? 'open').toLowerCase();
    return s != 'completed' && s != 'done' && s != 'cancelled';
  }

  static Color statusColor(String? s) {
    switch ((s ?? '').toLowerCase()) {
      case 'completed':
      case 'done':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      case 'in_progress':
        return AppColors.info;
      default:
        return AppColors.warning;
    }
  }

  static Color priorityColor(String? p) {
    switch ((p ?? '').toLowerCase()) {
      case 'urgent':
      case 'high':
        return AppColors.error;
      case 'low':
        return AppColors.info;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (showPartyName && item.partyName != null) item.partyName!,
      if (item.dueDate != null) 'Due ${item.dueDate}',
      if (item.actionType != null) item.actionType!,
    ].where((e) => e.isNotEmpty).join(' · ');

    return AppCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.displayTitle,
                    style: AppType.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                _chip(item.status ?? 'open', statusColor(item.status)),
                const SizedBox(width: 6),
                _chip(item.priority ?? 'medium', priorityColor(item.priority)),
              ],
            ),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(meta, style: AppType.meta.copyWith(color: AppColors.inkMuted)),
            ],
            if (item.description != null || item.notes != null) ...[
              const SizedBox(height: 6),
              Text(item.description ?? item.notes!, style: AppType.meta),
            ],
            if (onTap != null) ...[
              const SizedBox(height: 8),
              Text(
                'Tap to mark completed',
                style: AppType.micro.copyWith(
                  fontWeight: FontWeight.w500,
                  color: AppColors.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: AppType.micro.copyWith(
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// The "Mark completed" dialog plus the update call.
///
/// Returns `true` when the follow-up was actually marked completed.
Future<bool> showCompleteFollowupDialog(
  BuildContext context,
  MarketingService service,
  Followup item,
) async {
  final noteCtrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        'Mark completed',
        style: AppType.body.copyWith(fontWeight: FontWeight.w600),
      ),
      content: VoiceTextField(
        controller: noteCtrl,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'Completion note (optional)',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Complete'),
        ),
      ],
    ),
  );
  if (ok != true) return false;

  final result = await service.updateFollowup(item.id, {
    'status': 'completed',
    if (noteCtrl.text.trim().isNotEmpty)
      'completion_note': noteCtrl.text.trim(),
  });
  if (!context.mounted) return false;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        result.success
            ? 'Marked completed.'
            : (result.message ?? 'Could not update follow-up.'),
      ),
    ),
  );
  return result.success;
}
