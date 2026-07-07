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
    final inTime = DateTime.tryParse(requestedInTime ?? '');
    final outTime = DateTime.tryParse(requestedOutTime ?? '');
    if (inTime == null || outTime == null) {
      return false;
    }
    return outTime.isBefore(inTime);
  }

  bool get canTreatAsActiveCheckIn => hasCheckIn && !hasCheckOut && !isRejected;

  String get dayLabel {
    final parsed = DateTime.tryParse(attDate);
    if (parsed == null) return 'Unknown';
    return DateFormat('EEEE').format(parsed);
  }

  String? _formatTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(raw);
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

  static AttendanceRequestRecord fromJson(Map<String, dynamic> json) {
    return AttendanceRequestRecord(
      id: _toInt(json['id']) ?? 0,
      attDate: (json['attDate'] ?? '').toString(),
      requestType: (json['requestType'] ?? 'self_punch').toString(),
      status: (json['status'] ?? 'requested').toString(),
      requestedInTime: json['requestedInTime']?.toString(),
      requestedOutTime: json['requestedOutTime']?.toString(),
      deviceType: json['deviceType']?.toString(),
      workflowStage: json['workflowStage']?.toString(),
      supervisorStatus: json['supervisorStatus']?.toString(),
      hrStatus: json['hrStatus']?.toString(),
      address: json['address']?.toString(),
      latitude: _toDouble(json['lat']),
      longitude: _toDouble(json['lng']),
      faceVerified: json['faceVerified'] == true || json['face_verified'] == true,
      createdAt: json['createdAt']?.toString(),
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
