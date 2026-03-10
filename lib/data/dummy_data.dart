class DummyData {
  // Current user
  static const String userName = 'John Anderson';
  static const String userEmail = 'john.anderson@pphl.com';
  static const String userDesignation = 'Senior Software Engineer';
  static const String userDepartment = 'Engineering';
  static const String userEmployeeId = 'EMP-2024-0042';
  static const String userAvatar = 'JA';

  // Attendance stats for this month
  static const int totalWorkingDays = 22;
  static const int presentDays = 18;
  static const int absentDays = 1;
  static const int lateDays = 2;
  static const int leaveDays = 1;
  static const double attendancePercentage = 81.8;

  // Today's status
  static const bool isClockedIn = false;
  static const String todayCheckIn = '--:--';
  static const String todayCheckOut = '--:--';
  static const String todayWorkHours = '0h 0m';

  // Office location
  static const double officeLatitude = 23.8103;
  static const double officeLongitude = 90.4125;
  static const String officeAddress = 'PPHL Tower, Dhaka, Bangladesh';
  static const double allowedRadius = 200; // meters

  // Recent attendance records
  static List<Map<String, dynamic>> recentAttendance = [
    {
      'date': '2026-02-24',
      'day': 'Monday',
      'checkIn': '09:02 AM',
      'checkOut': '06:15 PM',
      'status': 'present',
      'workHours': '9h 13m',
      'verifiedBy': 'Face + Location',
    },
    {
      'date': '2026-02-23',
      'day': 'Sunday',
      'checkIn': '--',
      'checkOut': '--',
      'status': 'weekend',
      'workHours': '--',
      'verifiedBy': '--',
    },
    {
      'date': '2026-02-22',
      'day': 'Saturday',
      'checkIn': '--',
      'checkOut': '--',
      'status': 'weekend',
      'workHours': '--',
      'verifiedBy': '--',
    },
    {
      'date': '2026-02-21',
      'day': 'Friday',
      'checkIn': '09:35 AM',
      'checkOut': '06:05 PM',
      'status': 'late',
      'workHours': '8h 30m',
      'verifiedBy': 'Face + Location',
    },
    {
      'date': '2026-02-20',
      'day': 'Thursday',
      'checkIn': '08:55 AM',
      'checkOut': '06:30 PM',
      'status': 'present',
      'workHours': '9h 35m',
      'verifiedBy': 'Face + Location',
    },
    {
      'date': '2026-02-19',
      'day': 'Wednesday',
      'checkIn': '--',
      'checkOut': '--',
      'status': 'leave',
      'workHours': '--',
      'verifiedBy': '--',
    },
    {
      'date': '2026-02-18',
      'day': 'Tuesday',
      'checkIn': '08:58 AM',
      'checkOut': '06:10 PM',
      'status': 'present',
      'workHours': '9h 12m',
      'verifiedBy': 'Face + Location',
    },
    {
      'date': '2026-02-17',
      'day': 'Monday',
      'checkIn': '09:00 AM',
      'checkOut': '06:00 PM',
      'status': 'present',
      'workHours': '9h 00m',
      'verifiedBy': 'Face + Location',
    },
    {
      'date': '2026-02-16',
      'day': 'Sunday',
      'checkIn': '--',
      'checkOut': '--',
      'status': 'weekend',
      'workHours': '--',
      'verifiedBy': '--',
    },
    {
      'date': '2026-02-15',
      'day': 'Saturday',
      'checkIn': '--',
      'checkOut': '--',
      'status': 'weekend',
      'workHours': '--',
      'verifiedBy': '--',
    },
  ];

  // Weekly work hours (for chart)
  static List<Map<String, dynamic>> weeklyHours = [
    {'day': 'Mon', 'hours': 9.0},
    {'day': 'Tue', 'hours': 9.2},
    {'day': 'Wed', 'hours': 0.0},
    {'day': 'Thu', 'hours': 9.5},
    {'day': 'Fri', 'hours': 8.5},
    {'day': 'Sat', 'hours': 0.0},
    {'day': 'Sun', 'hours': 0.0},
  ];

  // Notifications
  static List<Map<String, dynamic>> notifications = [
    {
      'title': 'Attendance Reminder',
      'message': 'Don\'t forget to check in today!',
      'time': '8:30 AM',
      'icon': 'alarm',
      'isRead': false,
    },
    {
      'title': 'Leave Approved',
      'message': 'Your leave request for Feb 19 has been approved.',
      'time': 'Yesterday',
      'icon': 'check_circle',
      'isRead': true,
    },
    {
      'title': 'Late Arrival Warning',
      'message': 'You arrived 35 minutes late on Feb 21.',
      'time': '2 days ago',
      'icon': 'warning',
      'isRead': true,
    },
    {
      'title': 'Monthly Report',
      'message': 'January 2026 attendance report is now available.',
      'time': '1 week ago',
      'icon': 'description',
      'isRead': true,
    },
  ];

  // Team members (for manager view placeholder)
  static List<Map<String, dynamic>> teamMembers = [
    {'name': 'Sarah Wilson', 'avatar': 'SW', 'status': 'present', 'checkIn': '08:45 AM'},
    {'name': 'Mike Chen', 'avatar': 'MC', 'status': 'present', 'checkIn': '09:00 AM'},
    {'name': 'Emily Davis', 'avatar': 'ED', 'status': 'late', 'checkIn': '09:42 AM'},
    {'name': 'Alex Kumar', 'avatar': 'AK', 'status': 'absent', 'checkIn': '--'},
    {'name': 'Lisa Park', 'avatar': 'LP', 'status': 'present', 'checkIn': '08:55 AM'},
    {'name': 'David Brown', 'avatar': 'DB', 'status': 'leave', 'checkIn': '--'},
  ];
}
