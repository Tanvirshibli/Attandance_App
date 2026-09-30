import 'package:flutter/material.dart';

import '../../config/app_design.dart';

/// A value the app derives itself and shows without letting the user change it.
///
/// Used for the fields the marketing forms auto-resolve from the logged-in
/// employee (zone, company, sector, market) and for the generated record code.
/// A `SearchableSelectField` with `enabled: false` would still render as a field
/// you could tap; this renders as a settled fact instead — no mic, no dropdown
/// affordance, and a lock so read-only is obvious at a glance rather than
/// something the officer has to discover by tapping and finding nothing.
class ReadOnlyField extends StatelessWidget {
  const ReadOnlyField({
    super.key,
    required this.label,
    required this.icon,
    this.value,
    this.hint,
  });

  final String label;
  final IconData icon;

  /// The resolved value. Null or blank renders [hint] instead, which is how an
  /// unresolvable field says so without pretending to have a value.
  final String? value;

  /// Shown in place of [value] when there is nothing to display.
  final String? hint;

  bool get _hasValue => (value ?? '').trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final text = _hasValue ? value!.trim() : (hint ?? 'Not set');
    final color = _hasValue ? AppColors.ink : AppColors.inkFaint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            label,
            style: AppType.meta.copyWith(
              fontWeight: FontWeight.w500,
              color: AppColors.inkMuted,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.sm + 2,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceSunk,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.inkFaint),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: AppType.bodySm.copyWith(color: color),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.lock_outline,
                size: 15,
                color: AppColors.inkFaint,
              ),
            ],
          ),
        ),
      ],
    );
  }
}