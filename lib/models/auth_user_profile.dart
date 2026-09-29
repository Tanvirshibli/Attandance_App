import 'face_registration_data.dart';

class AuthUserProfile {
  const AuthUserProfile({
    required this.name,
    required this.email,
    required this.sector,
    required this.designation,
    required this.department,
    required this.employeeId,
    required this.phone,
    required this.joiningDate,
    this.canonicalEmployeeId,
    this.faceRegistration,
    this.zoneIds = const [],
    this.zoneName,
  });

  final String name;
  final String email;
  final String sector;
  final String designation;
  final String department;
  final String employeeId;
  final String phone;
  final String joiningDate;
  final int? canonicalEmployeeId;
  final FaceRegistrationData? faceRegistration;

  /// Hierarchy zones of the logged-in employee (company > zone > sector > depot).
  /// HRM stores this as a jsonb array, so an employee can hold several zones and
  /// sees the union of their data. Empty until the HRM profile populates it;
  /// filtering degrades gracefully while absent.
  final List<int> zoneIds;
  final String? zoneName;

  /// The first assigned zone, for the legacy single-zone call sites that have
  /// not moved to [ZoneScope] yet.
  @Deprecated('Use zoneIds — the employee may hold several zones.')
  int? get zoneId => zoneIds.isEmpty ? null : zoneIds.first;

  String get avatarLetters {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      return 'NA';
    }

    final parts = trimmedName
        .split(RegExp(r'\s+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      return trimmedName.substring(0, 1).toUpperCase();
    }

    if (parts.length == 1) {
      final token = parts.first;
      return token.substring(0, token.length >= 2 ? 2 : 1).toUpperCase();
    }

    final first = parts.first.substring(0, 1);
    final second = parts[1].substring(0, 1);
    return (first + second).toUpperCase();
  }

  static AuthUserProfile fromJson(Map<String, dynamic> json) {
    final employee = _readMap(json['employee']);
    final facility = _readMap(json['current_facility']);

    return AuthUserProfile(
      name: _firstNonEmpty([
        _fullName(employee),
        json['name'],
        json['username'],
      ], fallback: 'User'),
      email: _firstNonEmpty([
        employee['email'],
        json['email'],
      ], fallback: 'N/A'),
      sector: _firstNonEmpty([
        _mapName(json['sector']),
        _mapName(facility['sector']),
        employee['sector'],
      ], fallback: 'N/A'),
      designation: _firstNonEmpty([
        _mapName(json['designation']),
        _mapName(facility['designation']),
        json['designation'],
        employee['designation'],
        employee['job_title'],
      ], fallback: 'N/A'),
      department: _firstNonEmpty([
        _mapName(json['department']),
        _mapName(facility['department']),
        json['department'],
        employee['department'],
      ], fallback: 'N/A'),
      employeeId: _firstNonEmpty([
        json['employee_id'],
        employee['emp_id'],
        employee['employee_id'],
      ], fallback: 'N/A'),
      phone: _firstNonEmpty([
        json['phone'],
        json['mobile'],
        employee['phone_number'],
        employee['phone'],
        employee['mobile'],
      ], fallback: 'N/A'),
      joiningDate: _firstNonEmpty([
        json['joiningDate'],
        json['date_of_joining'],
        facility['jDate'],
        facility['fDate'],
        employee['joiningDate'],
        employee['doj'],
        employee['date_of_joining'],
      ], fallback: 'N/A'),
      canonicalEmployeeId: _parseCanonicalEmployeeId(json, employee),
      faceRegistration: FaceRegistrationData.fromJson(json['face_registration']),
      zoneIds: _toPositiveIntList(
        json['zoneId'] ??
            json['zone_id'] ??
            employee['zoneId'] ??
            employee['zone_id'] ??
            facility['zoneId'] ??
            facility['zone_id'],
      ),
      zoneName: _firstNonEmpty([
        _mapName(json['zone']),
        _mapName(employee['zone']),
        json['zoneName'],
        json['zone_name'],
        employee['zoneName'],
        facility['zoneName'],
        facility['zone_name'],
      ], fallback: ''),
    );
  }

  static AuthUserProfile fallback() {
    return const AuthUserProfile(
      name: 'User',
      email: 'N/A',
      sector: 'N/A',
      designation: 'N/A',
      department: 'N/A',
      employeeId: 'N/A',
      phone: 'N/A',
      joiningDate: 'N/A',
      canonicalEmployeeId: null,
      faceRegistration: null,
    );
  }

  static int? _parseCanonicalEmployeeId(
    Map<String, dynamic> json,
    Map<String, dynamic> employee,
  ) {
    for (final value in [
      json['employeeId'],
      json['canonical_employee_id'],
      employee['id'],
      employee['employeeId'],
    ]) {
      final parsed = _toPositiveInt(value);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  /// HRM returns `user.zoneId` as a jsonb **array**. The previous parser ran
  /// `int.tryParse` on it, so `[1,2,3]` became null and every zone filter in
  /// the app silently degraded to "no zone" — zone scoping never ran at all.
  ///
  /// Also accepts a bare scalar or a comma-separated string so a single-zone
  /// payload from another source still parses. Order is preserved and
  /// duplicates dropped.
  static List<int> _toPositiveIntList(Object? value) {
    if (value == null) return const [];

    final raw = <Object?>[];
    if (value is List) {
      raw.addAll(value);
    } else if (value is String && value.contains(',')) {
      raw.addAll(value.split(','));
    } else {
      raw.add(value);
    }

    final ids = <int>[];
    final seen = <int>{};
    for (final item in raw) {
      final parsed = _toPositiveInt(item);
      if (parsed != null && seen.add(parsed)) {
        ids.add(parsed);
      }
    }
    return ids;
  }

  static int? _toPositiveInt(Object? value) {
    if (value is int) {
      return value > 0 ? value : null;
    }
    if (value is num) {
      final parsed = value.toInt();
      return parsed > 0 ? parsed : null;
    }
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed <= 0) {
      return null;
    }
    return parsed;
  }

  static Map<String, dynamic> _readMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    return <String, dynamic>{};
  }

  static String _mapName(Object? value) {
    if (value is Map<String, dynamic>) {
      return _firstNonEmpty([
        value['name'],
        value['nameEn'],
        value['title'],
      ], fallback: '');
    }

    final text = value?.toString().trim() ?? '';
    return text.toLowerCase() == 'null' ? '' : text;
  }

  static String _fullName(Map<String, dynamic> employee) {
    final firstName = employee['first_name']?.toString().trim() ?? '';
    final lastName = employee['last_name']?.toString().trim() ?? '';
    final fullName = '$firstName $lastName'.trim();
    return fullName;
  }

  static String _firstNonEmpty(
    List<Object?> values, {
    required String fallback,
  }) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }
    return fallback;
  }
}
