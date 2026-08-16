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

String _str(Object? v) => v?.toString().trim() ?? '';

String? _strOrNull(Object? v) {
  final s = v?.toString().trim();
  if (s == null || s.isEmpty || s == 'null') return null;
  return s;
}

List<Map<String, dynamic>> _mapList(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}

Map<String, dynamic>? _asMap(Object? raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return null;
}

String formatTripDateTime(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '—';
  final parsed = DateTime.tryParse(raw.trim());
  if (parsed == null) return raw;
  final local = parsed.isUtc ? parsed.toLocal() : parsed;
  return DateFormat('dd MMM yyyy, hh:mm a').format(local);
}

String formatTripDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '—';
  final parsed = DateTime.tryParse(raw.trim());
  if (parsed == null) return raw;
  final local = parsed.isUtc ? parsed.toLocal() : parsed;
  return DateFormat('dd MMM yyyy').format(local);
}

String tripStatusLabel(String status) {
  switch (status.toLowerCase()) {
    case 'intransit':
      return 'In transit';
    case 'delivered':
      return 'Delivered';
    case 'draft':
      return 'Draft';
    case 'cancelled':
    case 'canceled':
      return 'Cancelled';
    case 'archived':
      return 'Archived';
    default:
      return status.isEmpty ? 'Unknown' : status;
  }
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
    if (parsed == null) {
      return purchaseDate?.isNotEmpty == true ? purchaseDate! : '—';
    }
    return DateFormat('dd MMM yyyy').format(parsed);
  }

  factory VehicleSummary.fromJson(Map<String, dynamic> json) {
    return VehicleSummary(
      id: _toInt(json['id']),
      tVehicleNo: (json['tVehicleNo'] ?? json['t_vehicle_no'] ?? '').toString(),
      numberPlate:
          (json['numberPlate'] ?? json['number_plate'] ?? '').toString(),
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

class TripAreaPoint {
  const TripAreaPoint({required this.id, required this.name});

  final int id;
  final String name;

  factory TripAreaPoint.fromJson(Map<String, dynamic> json) {
    return TripAreaPoint(
      id: _toInt(json['id']),
      name: _str(json['area_name_en'] ?? json['area_name'] ?? json['name']),
    );
  }
}

class TripPerson {
  const TripPerson({
    required this.id,
    required this.employeeId,
    required this.name,
  });

  final int id;
  final int employeeId;
  final String name;

  factory TripPerson.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return TripPerson(
      id: _toInt(map['id']),
      employeeId: _toInt(map['employeeId'] ?? map['employee_id']),
      name: _str(map['employeeName'] ?? map['employee_name'] ?? map['name']),
    );
  }
}

class TripVehicleInfo {
  const TripVehicleInfo({
    required this.arrangement,
    required this.vehicleId,
    required this.plate,
    this.odometerStart,
    this.odometerEnd,
    this.tankCapacity,
    this.openingFuelQty,
    this.openingFuelIsFull = false,
    this.driver,
    this.helper,
  });

  final String arrangement;
  final int vehicleId;
  final String plate;
  final String? odometerStart;
  final String? odometerEnd;
  final String? tankCapacity;
  final String? openingFuelQty;
  final bool openingFuelIsFull;
  final TripPerson? driver;
  final TripPerson? helper;

  factory TripVehicleInfo.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    final nested = _asMap(map['vehicle']);
    final plate = _str(
      nested?['numberPlate'] ??
          nested?['tVehicleNo'] ??
          map['vehicleNumber'] ??
          map['numberPlate'],
    );
    final driver = _asMap(map['driver']);
    final helper = _asMap(map['helper']);
    return TripVehicleInfo(
      arrangement: _str(map['vehicleArrangement']),
      vehicleId: _toInt(nested?['id'] ?? map['vehicleId']),
      plate: plate,
      odometerStart: _strOrNull(map['odometerStart']),
      odometerEnd: _strOrNull(map['odometerEnd']),
      tankCapacity: _strOrNull(map['tank_capacity']),
      openingFuelQty: _strOrNull(map['opening_fuel_qty']),
      openingFuelIsFull: map['opening_fuel_is_full'] == true,
      driver: driver == null ? null : TripPerson.fromJson(driver),
      helper: helper == null ? null : TripPerson.fromJson(helper),
    );
  }
}

class TripCargo {
  const TripCargo({this.goods, this.qty, this.unitName});

  final String? goods;
  final String? qty;
  final String? unitName;

  factory TripCargo.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    final unit = _asMap(map['unit']);
    return TripCargo(
      goods: _strOrNull(map['goods']),
      qty: _strOrNull(map['qty']),
      unitName: _strOrNull(unit?['name']),
    );
  }
}

class TripCustomer {
  const TripCustomer({this.name, this.phone, this.billTotal = 0});

  final String? name;
  final String? phone;
  final double billTotal;

  factory TripCustomer.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    final info = _asMap(map['customerInfo']);
    final summary = _asMap(map['customerBillSummary']);
    return TripCustomer(
      name: _strOrNull(
        map['customerName'] ?? info?['tradeName'] ?? info?['name'],
      ),
      phone: _strOrNull(
        map['referencePhone'] ?? info?['phone'],
      ),
      billTotal: _toDouble(summary?['totalAmount']),
    );
  }
}

class TripStop {
  const TripStop({
    required this.id,
    required this.pointType,
    required this.areaName,
    this.sequence,
    this.reachTime,
    this.leaveTime,
    this.note,
    this.status,
  });

  final int id;
  final String pointType;
  final String areaName;
  final int? sequence;
  final String? reachTime;
  final String? leaveTime;
  final String? note;
  final String? status;

  factory TripStop.fromJson(Map<String, dynamic> json) {
    final area = _asMap(json['area']);
    return TripStop(
      id: _toInt(json['id']),
      pointType: _str(json['point_type']),
      areaName: _str(area?['area_name_en'] ?? area?['name']),
      sequence: json['loadUnloadSequence'] == null
          ? null
          : _toInt(json['loadUnloadSequence']),
      reachTime: _strOrNull(json['reach_time']),
      leaveTime: _strOrNull(json['leave_time']),
      note: _strOrNull(json['note']),
      status: _strOrNull(json['status']),
    );
  }
}

class TripFuelLine {
  const TripFuelLine({
    required this.id,
    this.voucherNo,
    this.fuelDate,
    this.qty = 0,
    this.unitPrice = 0,
    this.totalAmount = 0,
    this.fuelName,
    this.sourceType,
    this.status,
  });

  final int id;
  final String? voucherNo;
  final String? fuelDate;
  final double qty;
  final double unitPrice;
  final double totalAmount;
  final String? fuelName;
  final String? sourceType;
  final String? status;

  factory TripFuelLine.fromJson(Map<String, dynamic> json) {
    final fuel = _asMap(json['fuel']);
    return TripFuelLine(
      id: _toInt(json['id']),
      voucherNo: _strOrNull(json['voucher_no']),
      fuelDate: _strOrNull(json['fuel_date']),
      qty: _toDouble(json['fuel_qty']),
      unitPrice: _toDouble(json['unit_price']),
      totalAmount: _toDouble(json['total_amount']),
      fuelName: _strOrNull(fuel?['fuel_name']),
      sourceType: _strOrNull(json['source_type']),
      status: _strOrNull(json['status']),
    );
  }
}

class TripFuelCalc {
  const TripFuelCalc({
    this.consumedQty = 0,
    this.totalCost = 0,
    this.tripKm = 0,
    this.avgMileage = 0,
    this.method,
  });

  final double consumedQty;
  final double totalCost;
  final double tripKm;
  final double avgMileage;
  final String? method;

  factory TripFuelCalc.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return TripFuelCalc(
      consumedQty: _toDouble(map['trip_fuel_consumed_qty']),
      totalCost: _toDouble(map['trip_fuel_total_cost']),
      tripKm: _toDouble(map['trip_km']),
      avgMileage: _toDouble(map['avg_mileage']),
      method: _strOrNull(map['fuel_calc_method']),
    );
  }
}

class TripAdvance {
  const TripAdvance({
    required this.id,
    this.voucherNumber,
    this.issueDate,
    this.amount = 0,
    this.purpose,
    this.paymentMethod,
    this.status,
  });

  final int id;
  final String? voucherNumber;
  final String? issueDate;
  final double amount;
  final String? purpose;
  final String? paymentMethod;
  final String? status;

  factory TripAdvance.fromJson(Map<String, dynamic> json) {
    return TripAdvance(
      id: _toInt(json['id']),
      voucherNumber: _strOrNull(json['voucher_number']),
      issueDate: _strOrNull(json['issue_date']),
      amount: _toDouble(json['advance_amount']),
      purpose: _strOrNull(json['purpose']),
      paymentMethod: _strOrNull(json['payment_method']),
      status: _strOrNull(json['status']),
    );
  }
}

class TripSupplierLine {
  const TripSupplierLine({
    required this.id,
    this.tradeName,
    this.amount = 0,
    this.status,
    this.date,
  });

  final int id;
  final String? tradeName;
  final double amount;
  final String? status;
  final String? date;

  factory TripSupplierLine.fromJson(Map<String, dynamic> json) {
    final supplier = _asMap(json['supplier']);
    return TripSupplierLine(
      id: _toInt(json['id']),
      tradeName: _strOrNull(json['tradeName'] ?? supplier?['tradeName']),
      amount: _toDouble(json['amount']),
      status: _strOrNull(json['status']),
      date: _strOrNull(json['date']),
    );
  }
}

class TripTotals {
  const TripTotals({
    this.supplierAmount = 0,
    this.incomeAmount = 0,
    this.customerBillAmount = 0,
    this.expenseAmount = 0,
    this.advanceAmount = 0,
    this.outSideFuelQty = 0,
    this.outSideFuelAmount = 0,
  });

  final double supplierAmount;
  final double incomeAmount;
  final double customerBillAmount;
  final double expenseAmount;
  final double advanceAmount;
  final double outSideFuelQty;
  final double outSideFuelAmount;

  factory TripTotals.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return TripTotals(
      supplierAmount: _toDouble(map['supplierAmount']),
      incomeAmount: _toDouble(map['incomeAmount']),
      customerBillAmount: _toDouble(map['customerBillAmount']),
      expenseAmount: _toDouble(map['expenseAmount']),
      advanceAmount: _toDouble(map['advanceAmount']),
      outSideFuelQty: _toDouble(map['outSidefuelQty']),
      outSideFuelAmount: _toDouble(map['outSidefuelAmount']),
    );
  }
}

class Trip {
  const Trip({
    required this.id,
    required this.tripCode,
    required this.tripTitle,
    required this.status,
    this.tripType,
    this.startDateTime,
    this.unloadDateTime,
    this.note,
    this.loadPoints = const [],
    this.unloadPoints = const [],
    this.vehicle,
    this.cargo,
    this.customer,
    this.tripPoints = const [],
    this.fuelLines = const [],
    this.fuelCalc,
    this.advances = const [],
    this.suppliers = const [],
    this.totals,
  });

  final int id;
  final String tripCode;
  final String tripTitle;
  final String status;
  final String? tripType;
  final String? startDateTime;
  final String? unloadDateTime;
  final String? note;
  final List<TripAreaPoint> loadPoints;
  final List<TripAreaPoint> unloadPoints;
  final TripVehicleInfo? vehicle;
  final TripCargo? cargo;
  final TripCustomer? customer;
  final List<TripStop> tripPoints;
  final List<TripFuelLine> fuelLines;
  final TripFuelCalc? fuelCalc;
  final List<TripAdvance> advances;
  final List<TripSupplierLine> suppliers;
  final TripTotals? totals;

  String get plate => vehicle?.plate ?? '—';

  String get routeLabel {
    final load = loadPoints.map((p) => p.name).where((n) => n.isNotEmpty);
    final unload = unloadPoints.map((p) => p.name).where((n) => n.isNotEmpty);
    final from = load.isEmpty ? '—' : load.join(', ');
    final to = unload.isEmpty ? '—' : unload.join(', ');
    return '$from → $to';
  }

  String get statusLabel => tripStatusLabel(status);

  bool involvesEmployee(int employeeId) {
    if (employeeId <= 0) return false;
    final driverId = vehicle?.driver?.employeeId ?? 0;
    final helperId = vehicle?.helper?.employeeId ?? 0;
    return driverId == employeeId || helperId == employeeId;
  }

  bool involvesVehicle(int vehicleId) {
    if (vehicleId <= 0) return false;
    return (vehicle?.vehicleId ?? 0) == vehicleId;
  }

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      id: _toInt(json['id']),
      tripCode: _str(json['tripCode'] ?? json['trip_code']),
      tripTitle: _str(json['tripTitle'] ?? json['trip_title']),
      status: _str(json['status']),
      tripType: _strOrNull(json['tripType']),
      startDateTime: _strOrNull(json['startDateTime']),
      unloadDateTime: _strOrNull(json['unloadDateTime']),
      note: _strOrNull(json['note']),
      loadPoints: _mapList(json['loadPoints']).map(TripAreaPoint.fromJson).toList(),
      unloadPoints:
          _mapList(json['unloadPoints']).map(TripAreaPoint.fromJson).toList(),
      vehicle: TripVehicleInfo.fromJson(_asMap(json['vehicle'])),
      cargo: TripCargo.fromJson(_asMap(json['cargo'])),
      customer: TripCustomer.fromJson(_asMap(json['customer'])),
      tripPoints: _mapList(json['tripPoints']).map(TripStop.fromJson).toList(),
      fuelLines:
          _mapList(json['tripFuelDetails']).map(TripFuelLine.fromJson).toList(),
      fuelCalc: TripFuelCalc.fromJson(_asMap(json['fuelCalculation'])),
      advances:
          _mapList(json['suspenseIssues']).map(TripAdvance.fromJson).toList(),
      suppliers:
          _mapList(json['suppliers']).map(TripSupplierLine.fromJson).toList(),
      totals: TripTotals.fromJson(_asMap(json['totals'])),
    );
  }
}

class TripListPage {
  const TripListPage({
    required this.trips,
    required this.currentPage,
    required this.lastPage,
    required this.total,
    this.message,
    this.statusCounts = const {},
  });

  final List<Trip> trips;
  final int currentPage;
  final int lastPage;
  final int total;
  final String? message;
  final Map<String, int> statusCounts;

  bool get hasMore => currentPage < lastPage;

  factory TripListPage.fromJson(Map<String, dynamic> json) {
    final meta = _asMap(json['meta']) ?? const <String, dynamic>{};
    final statusRaw = _asMap(meta['totalStatus']) ?? const <String, dynamic>{};
    final statusCounts = <String, int>{};
    for (final entry in statusRaw.entries) {
      statusCounts[entry.key] = _toInt(entry.value);
    }
    return TripListPage(
      trips: _mapList(json['data']).map(Trip.fromJson).toList(),
      currentPage: _toInt(meta['current_page'] ?? 1),
      lastPage: _toInt(meta['last_page'] ?? 1),
      total: _toInt(meta['total'] ?? meta['totalTrips']),
      message: _strOrNull(json['message']),
      statusCounts: statusCounts,
    );
  }
}
