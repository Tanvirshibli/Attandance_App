class LeaveType {
  const LeaveType({
    required this.id,
    required this.name,
    this.isPaid = true,
  });

  final int id;
  final String name;
  final bool isPaid;

  factory LeaveType.fromJson(Map<String, dynamic> json) {
    return LeaveType(
      id: _toInt(json['id']),
      name: (json['name'] ?? 'Leave').toString(),
      isPaid: json['isPaid'] == true || json['isPaid'] == 1,
    );
  }

  static int _toInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}
