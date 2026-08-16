import 'dart:convert';
import 'dart:io';

import 'package:employee_attendance/models/vehicle_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, dynamic> fixture;

  setUpAll(() {
    final file = File('test/fixtures/trip_tp_0954.json');
    fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  });

  test('parses trimmed TP-0954 list page and trip fields', () {
    final page = TripListPage.fromJson(fixture);

    expect(page.currentPage, 1);
    expect(page.lastPage, 5);
    expect(page.total, 897);
    expect(page.hasMore, isTrue);
    expect(page.statusCounts['inTransit'], 3);
    expect(page.trips, hasLength(1));

    final trip = page.trips.single;
    expect(trip.id, 954);
    expect(trip.tripCode, 'TP-0954');
    expect(trip.tripTitle, 'Mono Feedmill to Hazigong');
    expect(trip.status, 'draft');
    expect(trip.statusLabel, 'Draft');
    expect(trip.unloadDateTime, isNull);
    expect(trip.note, 'commercial feed');
    expect(trip.plate, 'DM-U-11-6231');
    expect(trip.routeLabel, 'Mono Feedmill → Hazigong');

    expect(trip.vehicle?.arrangement, 'ownVehicle');
    expect(trip.vehicle?.odometerStart, '46351.000');
    expect(trip.vehicle?.odometerEnd, isNull);
    expect(trip.vehicle?.driver?.employeeId, 1896);
    expect(trip.vehicle?.helper?.employeeId, 1924);

    expect(trip.cargo?.goods, 'feed');
    expect(trip.cargo?.qty, '14000.000');
    expect(trip.cargo?.unitName, 'Pcs');

    expect(trip.customer?.name, 'Modina Po:');
    expect(trip.customer?.phone, '01705304573');
    expect(trip.customer?.billTotal, 14500);

    expect(trip.tripPoints, hasLength(1));
    expect(trip.tripPoints.first.pointType, 'load');
    expect(trip.tripPoints.first.areaName, 'Mono Feedmill');

    expect(trip.fuelLines, hasLength(1));
    expect(trip.fuelLines.first.qty, 2);
    expect(trip.fuelLines.first.totalAmount, 288);
    expect(trip.fuelLines.first.fuelName, 'Diesel');

    expect(trip.fuelCalc?.method, 'full_to_full');
    expect(trip.advances.single.voucherNumber, 'TSI26070921');
    expect(trip.advances.single.amount, 1);
    expect(trip.totals?.customerBillAmount, 14500);
    expect(trip.totals?.outSideFuelAmount, 288);
    expect(trip.suppliers.single.amount, 1500);
  });

  test('TP-0954 involves vehicle 78 only', () {
    final trip = TripListPage.fromJson(fixture).trips.single;

    expect(trip.involvesVehicle(78), isTrue);
    expect(trip.involvesVehicle(34), isFalse);
    expect(trip.involvesVehicle(0), isFalse);
  });

  test('parses active vehicle list and maintenance history', () {
    final listRaw = jsonDecode(
      File('test/fixtures/vehicle_active_list.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final vehicles = (listRaw['data'] as List)
        .whereType<Map>()
        .map((e) => VehicleSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    expect(vehicles, hasLength(1));
    expect(vehicles.single.id, 34);
    expect(vehicles.single.displayPlate, 'DM-DA-12-6403');
    expect(vehicles.single.formattedPurchaseDate, '19 May 2025');

    final maintRaw = jsonDecode(
      File('test/fixtures/vehicle_maintenance_34.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final history = VehicleMaintenanceHistory.fromJson(maintRaw);
    expect(history.vehicleId, 34);
    expect(history.total, 1);
    expect(history.jobs, hasLength(1));
    expect(history.jobs.single.jobNo, 'VMJ26070175');
    expect(history.jobs.single.jobTitle, 'Wearing');
    expect(history.jobs.single.grandTotal, 192.73);
    expect(history.jobs.single.parts.single.name, 'Parking light Bulb');
    expect(history.jobs.single.parts.single.qty, 3);
  });
}
