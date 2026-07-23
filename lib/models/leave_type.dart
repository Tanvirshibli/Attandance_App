class LeaveType {
  const LeaveType({
    required this.id,
    required this.name,
    this.code,
    this.isPaid = true,
  });

  final int id;
  final String name;
  final String? code;
  final bool isPaid;

  factory LeaveType.fromJson(Map<String, dynamic> json) {
    final rawCode = json['code'];
    String? code;
    if (rawCode != null && rawCode.toString().trim().isNotEmpty) {
      code = rawCode.toString().trim();
    }

    return LeaveType(
      id: _toInt(json['id']),
      name: (json['lName'] ??
              json['leaveName'] ??
              json['leave_name'] ??
              json['name'] ??
              'Leave')
          .toString()
          .trim(),
      code: code,
      isPaid: json['isPaid'] == true ||
          json['isPaid'] == 1 ||
          json['is_paid'] == true ||
          json['is_paid'] == 1,
    );
  }

  static int _toInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}
