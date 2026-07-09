import 'package:intl/intl.dart';

class AttendanceRequestRecord {
  const AttendanceRequestRecord({
    required this.id,
    required this.attDate,
    required this.requestType,
    required this.status,
    this.requestedInTime,
    this.requestedOutTime,
    this.deviceType,
    this.workflowStage,
    this.supervisorStatus,
    this.hrStatus,
    this.address,
    this.latitude,
    this.longitude,
    this.faceVerified,
    this.createdAt,
  });

  final int id;
  final String attDate;
  final String requestType;
  final String status;
  final String? requestedInTime;
  final String? requestedOutTime;
  final String? deviceType;
  final String? workflowStage;
  final String? supervisorStatus;
  final String? hrStatus;
  final String? address;
  final double? latitude;
  final double? longitude;
  final bool? faceVerified;
  final String? createdAt;

  bool get isRejected => status.toLowerCase() == 'rejected';

  bool get hasCheckIn => checkInText != '--';

  bool get hasCheckOut => checkOutText != '--' && !hasInvalidChronology;

  bool get hasInvalidChronology {
    final inTime = parseFlexibleDateTime(requestedInTime);
    final outTime = parseFlexibleDateTime(requestedOutTime);
    if (inTime == null || outTime == null) {
      return false;
    }
    return outTime.isBefore(inTime);
  }

  bool get canTreatAsActiveCheckIn => hasCheckIn && !hasCheckOut && !isRejected;

  /// Date-only calendar day for [attDate], or null if unparseable.
  DateTime? get attDateOnly {
    final parsed = parseFlexibleDateTime(attDate) ?? DateTime.tryParse(attDate);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  bool isSameCalendarDay(DateTime day) {
    final mine = attDateOnly;
    if (mine == null) return false;
    return mine.year == day.year &&
        mine.month == day.month &&
        mine.day == day.day;
  }

  String get dayLabel {
    final parsed = attDateOnly;
    if (parsed == null) return 'Unknown';
    return DateFormat('EEEE').format(parsed);
  }

  String? _formatTime(String? raw) {
    final parsed = parseFlexibleDateTime(raw);
    if (parsed == null) {
      return null;
    }
    return DateFormat('hh:mm a').format(parsed);
  }

  String get checkInText => _formatTime(requestedInTime) ?? '--';
  String get checkOutText => _formatTime(requestedOutTime) ?? '--';

  Map<String, dynamic> toTileRecord() {
    return {
      'id': id,
      'date': attDate,
      'day': dayLabel,
      'checkIn': checkInText,
      'checkOut': checkOutText,
      'status': status.toLowerCase(),
      'workHours': '--',
      'verifiedBy': workflowStage ?? requestType.replaceAll('_', ' '),
    };
  }

  /// Parses ISO, `Y-m-d H:i:s`, `Y-m-d`, and time-only (`H:i:s` / `H:i`) strings.
  static DateTime? parseFlexibleDateTime(String? raw) {
    if (raw == null) return null;
    final value = raw.trim();
    if (value.isEmpty) return null;

    final iso = DateTime.tryParse(value);
    if (iso != null) return iso;

    // Space-separated datetime without T (common Laravel format).
    final withT = value.contains(' ') && !value.contains('T')
        ? value.replaceFirst(' ', 'T')
        : null;
    if (withT != null) {
      final parsed = DateTime.tryParse(withT);
      if (parsed != null) return parsed;
    }

    // Time-only: HH:mm:ss or HH:mm — anchor to today.
    final timeOnly = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(value);
    if (timeOnly != null) {
      final now = DateTime.now();
      final hour = int.tryParse(timeOnly.group(1)!) ?? 0;
      final minute = int.tryParse(timeOnly.group(2)!) ?? 0;
      final second = int.tryParse(timeOnly.group(3) ?? '0') ?? 0;
      if (hour > 23 || minute > 59 || second > 59) return null;
      return DateTime(now.year, now.month, now.day, hour, minute, second);
    }

    return null;
  }

  static AttendanceRequestRecord fromJson(Map<String, dynamic> json) {
    return AttendanceRequestRecord(
      id: _toInt(json['id']) ?? 0,
      attDate: (json['attDate'] ?? json['att_date'] ?? '').toString(),
      requestType:
          (json['requestType'] ?? json['request_type'] ?? 'self_punch').toString(),
      status: (json['status'] ?? 'requested').toString(),
      requestedInTime:
          (json['requestedInTime'] ?? json['requested_in_time'])?.toString(),
      requestedOutTime:
          (json['requestedOutTime'] ?? json['requested_out_time'])?.toString(),
      deviceType: (json['deviceType'] ?? json['device_type'])?.toString(),
      workflowStage:
          (json['workflowStage'] ?? json['workflow_stage'])?.toString(),
      supervisorStatus:
          (json['supervisorStatus'] ?? json['supervisor_status'])?.toString(),
      hrStatus: (json['hrStatus'] ?? json['hr_status'])?.toString(),
      address: json['address']?.toString(),
      latitude: _toDouble(json['lat']),
      longitude: _toDouble(json['lng']),
      faceVerified:
          json['faceVerified'] == true || json['face_verified'] == true,
      createdAt: (json['createdAt'] ?? json['created_at'])?.toString(),
    );
  }

  static double? _toDouble(Object? value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int? _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
