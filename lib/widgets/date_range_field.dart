import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../config/theme.dart';
import 'section_card.dart';

class DateRangeField extends StatelessWidget {
  const DateRangeField({
    super.key,
    required this.from,
    required this.to,
    required this.onChanged,
  });

  final DateTime from;
  final DateTime to;
  final void Function(DateTime from, DateTime to) onChanged;

  Future<void> _pickDate(
    BuildContext context, {
    required bool isFrom,
  }) async {
    final initial = isFrom ? from : to;
    final firstDate = DateTime(2020);
    final lastDate = DateTime.now().add(const Duration(days: 365));

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
    );

    if (picked == null) return;

    if (isFrom) {
      final newTo = picked.isAfter(to) ? picked : to;
      onChanged(picked, newTo);
    } else {
      final newFrom = picked.isBefore(from) ? picked : from;
      onChanged(newFrom, picked);
    }
  }

  String _fmt(DateTime d) => DateFormat('dd MMM yyyy').format(d);

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _dateTile(
              context,
              label: 'From',
              value: _fmt(from),
              onTap: () => _pickDate(context, isFrom: true),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_forward_rounded,
                size: 18, color: AppColors.textHint),
          ),
          Expanded(
            child: _dateTile(
              context,
              label: 'To',
              value: _fmt(to),
              onTap: () => _pickDate(context, isFrom: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateTile(
    BuildContext context, {
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 10,
                color: AppColors.textHint,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
