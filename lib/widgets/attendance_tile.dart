import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';

class AttendanceTile extends StatelessWidget {
  final Map<String, dynamic> record;

  const AttendanceTile({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final status = record['status'] as String;
    final statusColor = _getStatusColor(status);
    final statusIcon = _getStatusIcon(status);
    final badge = _StatusBadge(
      status: status,
      statusColor: statusColor,
      statusIcon: statusIcon,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _getDay(record['date'] as String),
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                    height: 1.2,
                  ),
                ),
                Text(
                  _getMonth(record['date'] as String),
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        record['day'] as String,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    badge,
                  ],
                ),
                const SizedBox(height: 4),
                _buildTimeRow(status),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeRow(String status) {
    if (record['checkIn'] != '--') {
      return Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.login_rounded, size: 12, color: AppColors.textHint),
              const SizedBox(width: 4),
              Text(
                record['checkIn'] as String,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.logout_rounded, size: 12, color: AppColors.textHint),
              const SizedBox(width: 4),
              Text(
                record['checkOut'] as String,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Text(
      status == 'weekend'
          ? 'Weekend'
          : status == 'leave'
              ? 'On Leave'
              : status == 'requested'
                  ? 'Awaiting approval'
                  : 'Absent',
      style: GoogleFonts.poppins(
        fontSize: 11,
        color: AppColors.textHint,
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'present':
        return AppColors.success;
      case 'absent':
        return AppColors.error;
      case 'late':
        return AppColors.warning;
      case 'leave':
        return AppColors.info;
      case 'weekend':
        return AppColors.textHint;
      case 'requested':
        return AppColors.warning;
      default:
        return AppColors.textHint;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'present':
        return Icons.check_circle_outline;
      case 'absent':
        return Icons.cancel_outlined;
      case 'late':
        return Icons.watch_later_outlined;
      case 'leave':
        return Icons.event_busy_outlined;
      case 'weekend':
        return Icons.weekend_outlined;
      case 'requested':
        return Icons.hourglass_top_rounded;
      default:
        return Icons.circle_outlined;
    }
  }

  String _getDay(String dateStr) {
    return dateStr.split('-').last;
  }

  String _getMonth(String dateStr) {
    final months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final month = int.parse(dateStr.split('-')[1]);
    return months[month];
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.status,
    required this.statusColor,
    required this.statusIcon,
  });

  final String status;
  final Color statusColor;
  final IconData statusIcon;

  @override
  Widget build(BuildContext context) {
    final label = status.isEmpty
        ? status
        : '${status[0].toUpperCase()}${status.substring(1)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, size: 12, color: statusColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }
}
