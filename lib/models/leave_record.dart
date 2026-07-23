import 'package:intl/intl.dart';

class LeaveRecord {
  const LeaveRecord({
    required this.id,
    required this.leaveTypeName,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.reason,
    this.duration,
  });

  final int id;
  final String leaveTypeName;
  final String startDate;
  final String endDate;
  final String status;
  final String? reason;
  final int? duration;

  String get dateRangeLabel {
    final start = DateTime.tryParse(startDate);
    final end = DateTime.tryParse(endDate);
    if (start == null || end == null) return '$startDate - $endDate';
    final fmt = DateFormat('dd MMM yyyy');
    if (startDate == endDate) return fmt.format(start);
    return '${fmt.format(start)} - ${fmt.format(end)}';
  }

  factory LeaveRecord.fromJson(Map<String, dynamic> json) {
    final leaveType = json['leave_type'] ?? json['leaveType'];
    String typeName = 'Leave';
    if (leaveType is Map<String, dynamic>) {
      typeName = (leaveType['lName'] ??
              leaveType['leaveName'] ??
              leaveType['leave_name'] ??
              leaveType['name'] ??
              'Leave')
          .toString();
    }

    return LeaveRecord(
      id: _toInt(json['id']),
      leaveTypeName: typeName,
      startDate: (json['startDate'] ?? '').toString(),
      endDate: (json['endDate'] ?? '').toString(),
      status: (json['status'] ?? 'pending').toString(),
      reason: json['reason']?.toString(),
      duration: _toIntNullable(json['duration']),
    );
  }

  static int _toInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static int? _toIntNullable(Object? v) {
    if (v == null) return null;
    return _toInt(v);
  }
}
