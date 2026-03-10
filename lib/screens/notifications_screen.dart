import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';
import '../data/dummy_data.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Header
          SliverToBoxAdapter(child: _buildHeader(context)),

          // Today's section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: FadeInUp(
                delay: const Duration(milliseconds: 200),
                duration: const Duration(milliseconds: 400),
                child: Text(
                  'Today',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),

          // Notification items
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final notif = DummyData.notifications[index];
                return FadeInUp(
                  delay: Duration(milliseconds: 250 + (index * 80)),
                  duration: const Duration(milliseconds: 400),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: _buildNotificationTile(notif),
                  ),
                );
              },
              childCount: DummyData.notifications.length,
            ),
          ),

          // Earlier section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: FadeInUp(
                delay: const Duration(milliseconds: 600),
                duration: const Duration(milliseconds: 400),
                child: Text(
                  'Earlier',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),

          // Earlier notifications (dummy extras)
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final extras = [
                  {
                    'title': 'System Update',
                    'message':
                        'AttendEase has been updated to v1.2.0 with new features.',
                    'time': '3 days ago',
                    'icon': 'update',
                    'isRead': true,
                  },
                  {
                    'title': 'Holiday Notice',
                    'message':
                        'Office will be closed on Feb 26 for National Holiday.',
                    'time': '5 days ago',
                    'icon': 'celebration',
                    'isRead': true,
                  },
                  {
                    'title': 'Face Data Updated',
                    'message':
                        'Your facial recognition data has been updated successfully.',
                    'time': '1 week ago',
                    'icon': 'face',
                    'isRead': true,
                  },
                ];
                return FadeInUp(
                  delay: Duration(milliseconds: 650 + (index * 80)),
                  duration: const Duration(milliseconds: 400),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: _buildNotificationTile(extras[index]),
                  ),
                );
              },
              childCount: 3,
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 16,
        20,
        24,
      ),
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: FadeInDown(
        duration: const Duration(milliseconds: 500),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Notifications',
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Mark all read',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationTile(Map<String, dynamic> notif) {
    final isRead = notif['isRead'] as bool;
    final iconName = notif['icon'] as String;

    IconData getIcon() {
      switch (iconName) {
        case 'alarm':
          return Icons.alarm_outlined;
        case 'check_circle':
          return Icons.check_circle_outline;
        case 'warning':
          return Icons.warning_amber_outlined;
        case 'description':
          return Icons.description_outlined;
        case 'update':
          return Icons.system_update_outlined;
        case 'celebration':
          return Icons.celebration_outlined;
        case 'face':
          return Icons.face_retouching_natural;
        default:
          return Icons.notifications_outlined;
      }
    }

    Color getIconColor() {
      switch (iconName) {
        case 'alarm':
          return AppColors.warning;
        case 'check_circle':
          return AppColors.success;
        case 'warning':
          return AppColors.error;
        case 'description':
          return AppColors.info;
        case 'update':
          return AppColors.primary;
        case 'celebration':
          return AppColors.accent;
        case 'face':
          return AppColors.success;
        default:
          return AppColors.primary;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isRead
            ? AppColors.surface
            : AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: isRead
            ? null
            : Border.all(
                color: AppColors.primary.withValues(alpha: 0.1),
              ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: getIconColor().withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(getIcon(), size: 20, color: getIconColor()),
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
                        notif['title'] as String,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight:
                              isRead ? FontWeight.w500 : FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (!isRead)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  notif['message'] as String,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  notif['time'] as String,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
