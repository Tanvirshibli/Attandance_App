import 'package:flutter/material.dart';

import '../services/endpoint_config_service.dart';
import '../widgets/ui/ui.dart';
import 'attendance_history_screen.dart';
import 'employee_services_hub_screen.dart';
import 'home_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';

/// The app shell: five tabs over an [IndexedStack], so every tab keeps its
/// scroll position and loaded data when you switch away and back.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    AttendanceHistoryScreen(),
    NotificationsScreen(),
    ProfileScreen(),
    EmployeeServicesHubScreen(showAsTabRoot: true),
  ];

  static const _navItems = <AppNavItem>[
    AppNavItem(
      label: 'Home',
      icon: PhosphorIconsDuotone.house,
      activeIcon: PhosphorIconsFill.house,
      color: AppColors.primary,
    ),
    AppNavItem(
      label: 'Attendance',
      icon: PhosphorIconsDuotone.calendarCheck,
      activeIcon: PhosphorIconsFill.calendarCheck,
      color: AppColors.mAttendance,
    ),
    AppNavItem(
      label: 'Alerts',
      icon: PhosphorIconsDuotone.bell,
      activeIcon: PhosphorIconsFill.bell,
      color: AppColors.mSales,
    ),
    AppNavItem(
      label: 'Profile',
      icon: PhosphorIconsDuotone.user,
      activeIcon: PhosphorIconsFill.user,
      color: AppColors.mHr,
    ),
    AppNavItem(
      label: 'Services',
      icon: PhosphorIconsDuotone.squaresFour,
      activeIcon: PhosphorIconsFill.squaresFour,
      color: AppColors.mPayments,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      EndpointConfigService.instance.refreshConfig().catchError((Object error) {
        debugPrint('Endpoint config refresh on resume failed: $error');
        return null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: AppBottomNav(
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          items: _navItems,
        ),
      ),
    );
  }
}
