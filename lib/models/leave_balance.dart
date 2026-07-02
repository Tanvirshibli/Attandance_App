class LeaveBalance {
  const LeaveBalance({
    required this.id,
    required this.leaveTypeName,
    required this.earned,
    required this.used,
    required this.balance,
    this.lastUpdated,
  });

  final int id;
  final String leaveTypeName;
  final double earned;
  final double used;
  final double balance;
  final String? lastUpdated;

  factory LeaveBalance.fromJson(Map<String, dynamic> json) {
    final leaveType = json['new_leave_type'] ?? json['newLeaveType'];
    String typeName = 'Leave';
    if (leaveType is Map<String, dynamic>) {
      typeName = (leaveType['name'] ?? leaveType['leaveTypeName'] ?? 'Leave')
          .toString();
    }

    return LeaveBalance(
      id: _toInt(json['id']),
      leaveTypeName: typeName,
      earned: _toDouble(json['earned']),
      used: _toDouble(json['used']),
      balance: _toDouble(json['balance']),
      lastUpdated: json['lastUpdated']?.toString(),
    );
  }

  static int _toInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double _toDouble(Object? v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }
}
