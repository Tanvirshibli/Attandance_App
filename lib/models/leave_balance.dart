class LeaveBalance {
  const LeaveBalance({
    required this.id,
    required this.leaveTypeName,
    required this.earned,
    required this.used,
    required this.balance,
    this.leaveTypeId,
    this.code,
    this.adjusted,
    this.year,
    this.lastUpdated,
  });

  final int id;
  final int? leaveTypeId;
  final String leaveTypeName;
  final double earned;
  final double used;
  final double balance;
  final String? code;
  final double? adjusted;
  final int? year;
  final String? lastUpdated;

  bool get hasGenericTypeName {
    final n = leaveTypeName.trim().toLowerCase();
    if (n.isEmpty || n == 'leave') return true;
    // Last-resort id placeholders from a prior enrich pass.
    if (RegExp(r'^leave type #\d+$').hasMatch(n)) return true;
    // Code used as temporary label still needs catalog enrichment.
    final c = code?.trim().toLowerCase();
    return c != null && c.isNotEmpty && n == c;
  }

  LeaveBalance copyWith({
    int? id,
    int? leaveTypeId,
    String? leaveTypeName,
    double? earned,
    double? used,
    double? balance,
    String? code,
    double? adjusted,
    int? year,
    String? lastUpdated,
  }) {
    return LeaveBalance(
      id: id ?? this.id,
      leaveTypeId: leaveTypeId ?? this.leaveTypeId,
      leaveTypeName: leaveTypeName ?? this.leaveTypeName,
      earned: earned ?? this.earned,
      used: used ?? this.used,
      balance: balance ?? this.balance,
      code: code ?? this.code,
      adjusted: adjusted ?? this.adjusted,
      year: year ?? this.year,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  factory LeaveBalance.fromJson(Map<String, dynamic> json) {
    final leaveType = json['new_leave_type'] ?? json['newLeaveType'];
    final typeMap = leaveType is Map<String, dynamic> ? leaveType : null;

    // Prefer column id: stocks often store legacy leave_types.id here.
    final leaveTypeId = _toIntNullable(
      json['newLeaveTypeId'] ??
          json['new_leave_type_id'] ??
          typeMap?['id'],
    );

    final code = _firstNonEmpty([
      typeMap?['code'],
      json['code'],
    ]);

    final typeName = _firstNonEmpty([
          typeMap?['leaveName'],
          typeMap?['leave_name'],
          typeMap?['lName'],
          typeMap?['name'],
          typeMap?['leaveTypeName'],
          json['leaveName'],
          json['leave_name'],
          json['lName'],
          json['name'],
          json['leaveTypeName'],
          ?code,
        ]) ??
        'Leave';

    final yearRaw = json['new_leave_year'] ?? json['newLeaveYear'];
    int? year;
    if (yearRaw is Map<String, dynamic>) {
      year = _toIntNullable(yearRaw['year']);
    }

    return LeaveBalance(
      id: _toInt(json['id']),
      leaveTypeId: leaveTypeId,
      leaveTypeName: typeName,
      earned: _toDouble(json['earned']),
      used: _toDouble(json['used']),
      balance: _toDouble(json['balance']),
      code: code,
      adjusted: _toDoubleNullable(json['adjusted']),
      year: year,
      lastUpdated: json['lastUpdated']?.toString(),
    );
  }

  static String? _firstNonEmpty(List<Object?> values) {
    for (final v in values) {
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  static int _toInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static int? _toIntNullable(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }

  static double _toDouble(Object? v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double? _toDoubleNullable(Object? v) {
    if (v == null) return null;
    return _toDouble(v);
  }
}
