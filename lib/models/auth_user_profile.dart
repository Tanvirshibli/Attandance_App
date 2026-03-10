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
    this.faceRegistration,
  });

  final String name;
  final String email;
  final String sector;
  final String designation;
  final String department;
  final String employeeId;
  final String phone;
  final String joiningDate;
  final FaceRegistrationData? faceRegistration;

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
        json['employeeId'],
        employee['emp_id'],
        employee['employeeId'],
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
      faceRegistration: FaceRegistrationData.fromJson(json['face_registration']),
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
      faceRegistration: null,
    );
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
