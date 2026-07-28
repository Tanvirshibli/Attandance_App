import 'package:intl/intl.dart';

import 'sales_models.dart' show moneyBdt;

int _toInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

double _toDouble(Object? v) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

List<Map<String, dynamic>> _mapList(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}

class VehicleSummary {
  const VehicleSummary({
    required this.id,
    required this.tVehicleNo,
    required this.numberPlate,
    this.purchaseDate,
  });

  final int id;
  final String tVehicleNo;
  final String numberPlate;
  final String? purchaseDate;

  String get displayPlate {
    final plate = numberPlate.trim();
    if (plate.isNotEmpty) return plate;
    return tVehicleNo.trim().isNotEmpty ? tVehicleNo.trim() : 'Vehicle #$id';
  }

  String get formattedPurchaseDate {
    final parsed = DateTime.tryParse(purchaseDate ?? '');
    if (parsed == null) return purchaseDate?.isNotEmpty == true ? purchaseDate! : '—';
    return DateFormat('dd MMM yyyy').format(parsed);
  }

  factory VehicleSummary.fromJson(Map<String, dynamic> json) {
    return VehicleSummary(
      id: _toInt(json['id']),
      tVehicleNo: (json['tVehicleNo'] ?? json['t_vehicle_no'] ?? '').toString(),
      numberPlate: (json['numberPlate'] ?? json['number_plate'] ?? '').toString(),
      purchaseDate: (json['purchaseDate'] ?? json['purchase_date'])?.toString(),
    );
  }
}

class VehicleMaintenancePart {
  const VehicleMaintenancePart({
    required this.id,
    required this.name,
    required this.qty,
    required this.price,
    required this.totalPrice,
    this.partId,
    this.unit,
  });

  final int id;
  final int? partId;
  final String name;
  final String? unit;
  final double qty;
  final double price;
  final double totalPrice;

  factory VehicleMaintenancePart.fromJson(Map<String, dynamic> json) {
    return VehicleMaintenancePart(
      id: _toInt(json['id']),
      partId: json['part_id'] == null ? null : _toInt(json['part_id']),
      name: (json['name'] ?? '').toString(),
      unit: json['unit']?.toString(),
      qty: _toDouble(json['qty']),
      price: _toDouble(json['price']),
      totalPrice: _toDouble(json['total_price']),
    );
  }
}

class VehicleMaintenanceJob {
  const VehicleMaintenanceJob({
    required this.id,
    required this.jobNo,
    required this.jobTitle,
    required this.status,
    required this.grandTotal,
    this.date,
    this.jobType,
    this.issueType,
    this.laborCost = 0,
    this.partsCost = 0,
    this.otherCost = 0,
    this.discount = 0,
    this.tax = 0,
    this.workshop,
    this.mechanic,
    this.performedBy,
    this.remarks,
    this.parts = const [],
  });

  final int id;
  final String? date;
  final String jobNo;
  final String jobTitle;
  final String? jobType;
  final String? issueType;
  final String status;
  final double laborCost;
  final double partsCost;
  final double otherCost;
  final double discount;
  final double tax;
  final double grandTotal;
  final String? workshop;
  final String? mechanic;
  final String? performedBy;
  final String? remarks;
  final List<VehicleMaintenancePart> parts;

  String get formattedDate {
    final parsed = DateTime.tryParse(date ?? '');
    if (parsed == null) return date?.isNotEmpty == true ? date! : '—';
    return DateFormat('dd MMM yyyy').format(parsed);
  }

  String get formattedGrandTotal => moneyBdt(grandTotal);

  factory VehicleMaintenanceJob.fromJson(Map<String, dynamic> json) {
    return VehicleMaintenanceJob(
      id: _toInt(json['id']),
      date: json['date']?.toString(),
      jobNo: (json['job_no'] ?? '').toString(),
      jobTitle: (json['job_title'] ?? '').toString(),
      jobType: json['job_type']?.toString(),
      issueType: json['issue_type']?.toString(),
      status: (json['status'] ?? '').toString(),
      laborCost: _toDouble(json['labor_cost']),
      partsCost: _toDouble(json['parts_cost']),
      otherCost: _toDouble(json['other_cost']),
      discount: _toDouble(json['discount']),
      tax: _toDouble(json['tax']),
      grandTotal: _toDouble(json['grand_total']),
      workshop: json['workshop']?.toString(),
      mechanic: json['mechanic']?.toString(),
      performedBy: json['performed_by']?.toString(),
      remarks: json['remarks']?.toString(),
      parts: _mapList(json['parts']).map(VehicleMaintenancePart.fromJson).toList(),
    );
  }
}

class VehicleMaintenanceHistory {
  const VehicleMaintenanceHistory({
    required this.vehicleId,
    required this.total,
    required this.jobs,
    this.message,
  });

  final int vehicleId;
  final int total;
  final String? message;
  final List<VehicleMaintenanceJob> jobs;

  factory VehicleMaintenanceHistory.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final info = data is Map ? data['maintenanceInfo'] : null;
    return VehicleMaintenanceHistory(
      vehicleId: _toInt(json['vehicleId'] ?? json['vehicle_id']),
      total: _toInt(json['total']),
      message: json['message']?.toString(),
      jobs: _mapList(info).map(VehicleMaintenanceJob.fromJson).toList(),
    );
  }
}
