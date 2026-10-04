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
    this.permissions = const [],
    this.roles = const [],
    this.isAdmin = false,
    this.isSuperAdmin = false,
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

  /// Role names granted to this account, resolved server-side through
  /// `user_has_roles -> roles`. Informational only — access is decided by
  /// [permissions], never by a role name, because a role may be renamed or
  /// renamed-and-remapped without the app shipping a new build.
  final List<String> roles;

  /// The flat, de-duplicated permission-name strings HRM resolved from this
  /// user's roles (`UserController::getSelf`, `GET /api/v1/get-my-info`).
  ///
  /// Stored as received. [PermissionService] lowercases on comparison, because
  /// the HRM web client compares case-insensitively and the two must agree on
  /// what a grant means.
  final List<String> permissions;

  /// Whether HRM flagged this account as an admin. Both arrive as the *strings*
  /// `"1"` / `"0"` rather than booleans, so the conversion is
  /// [parseAdminFlag]'s problem, not the caller's.
  final bool isAdmin;
  final bool isSuperAdmin;

  /// HRM sends `isAdmin` / `isSuperAdmin` as `"1"` / `"0"`, and the web client
  /// reads them with `Boolean(parseInt(v))`. Replicate that exactly, and treat
  /// a non-numeric truthy string as truthy rather than silently demoting an
  /// admin to an ordinary user.
  static bool parseAdminFlag(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase() ?? '';
    if (text.isEmpty) return false;
    if (text == '0' || text == 'false' || text == 'null') return false;
    return true;
  }

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
      faceRegistration: FaceRegistrationData.fromJson(
        json['face_registration'],
        // The engine (and its model width) may not be initialised when the
        // profile is parsed, so parse structurally here; the template version and
        // a verify-time length guard reject anything from a different model.
        expectedSize: null,
      ),
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
      roles: _roleNames(json),
      permissions: _toStringList(json['permissions']),
      isAdmin: parseAdminFlag(json['isAdmin'] ?? json['is_admin']),
      isSuperAdmin:
          parseAdminFlag(json['isSuperAdmin'] ?? json['is_super_admin']),
    );
  }

  /// Role names from the `roles2` eager-load on the HRM `User` model.
  ///
  /// `roles2` is a `belongsToMany` over `user_has_roles`, so each element is a
  /// role row carrying `roleName` (camelCase — this schema is hand-rolled, not
  /// Spatie's, so there is no `name`). A plain `roles` array is accepted as a
  /// fallback for a payload shaped that way instead.
  static List<String> _roleNames(Map<String, dynamic> json) {
    final roles2 = json['roles2'];
    if (roles2 is List) {
      return _dedupeNonEmpty(roles2.map(_roleNameOf).toList());
    }

    final roles = json['roles'];
    if (roles is List) {
      return _dedupeNonEmpty(roles.map(_roleNameOf).toList());
    }

    return const [];
  }

  static String _roleNameOf(Object? entry) {
    if (entry is Map) {
      return _firstNonEmpty([
        entry['roleName'],
        entry['name'],
        entry['role_name'],
      ], fallback: '');
    }
    return '';
  }

  /// A flat string list from JSON, tolerating a lone string and dropping
  /// blanks. Order is preserved and duplicates removed, matching the
  /// de-duplication HRM already applies server-side.
  static List<String> _toStringList(Object? value) {
    if (value == null) return const [];

    final raw = <Object?>[];
    if (value is List) {
      raw.addAll(value);
    } else if (value is String && value.contains(',')) {
      raw.addAll(value.split(','));
    } else {
      raw.add(value);
    }

    final texts = raw
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty && item.toLowerCase() != 'null')
        .toList();
    return _dedupeNonEmpty(texts);
  }

  static List<String> _dedupeNonEmpty(List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      if (value.isNotEmpty && seen.add(value)) {
        result.add(value);
      }
    }
    return List.unmodifiable(result);
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
