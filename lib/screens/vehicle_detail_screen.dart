import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import '../models/sales_models.dart' show moneyBdt, qtyFmt;
import '../models/vehicle_models.dart';
import '../widgets/gradient_screen_header.dart';
import '../widgets/section_card.dart';

class VehicleDetailScreen extends StatelessWidget {
  const VehicleDetailScreen({super.key, required this.trip});

  final Trip trip;

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'intransit':
        return AppColors.info;
      case 'delivered':
        return AppColors.success;
      case 'cancelled':
      case 'canceled':
        return AppColors.error;
      case 'archived':
        return AppColors.textHint;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(trip.status);
    final vehicle = trip.vehicle;
    final cargo = trip.cargo;
    final customer = trip.customer;
    final fuel = trip.fuelCalc;
    final totals = trip.totals;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: GradientScreenHeader(
              title: trip.tripCode.isEmpty ? 'Trip #${trip.id}' : trip.tripCode,
              subtitle: trip.tripTitle.isEmpty
                  ? trip.statusLabel
                  : '${trip.tripTitle} · ${trip.statusLabel}',
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                FadeInUp(
                  duration: const Duration(milliseconds: 250),
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                trip.tripTitle.isEmpty
                                    ? trip.tripCode
                                    : trip.tripTitle,
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                trip.statusLabel,
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (trip.tripType != null) ...[
                          const SizedBox(height: 8),
                          _metaRow('Type', trip.tripType!),
                        ],
                        _metaRow('Start', formatTripDateTime(trip.startDateTime)),
                        _metaRow('Unload', formatTripDateTime(trip.unloadDateTime)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FadeInUp(
                  delay: const Duration(milliseconds: 40),
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle('Route'),
                        _metaRow(
                          'Load',
                          trip.loadPoints
                                  .map((p) => p.name)
                                  .where((n) => n.isNotEmpty)
                                  .join(', ')
                                  .ifEmpty('—'),
                        ),
                        _metaRow(
                          'Unload',
                          trip.unloadPoints
                                  .map((p) => p.name)
                                  .where((n) => n.isNotEmpty)
                                  .join(', ')
                                  .ifEmpty('—'),
                        ),
                        if (trip.tripPoints.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Stops',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          for (final stop in trip.tripPoints)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    stop.pointType.toLowerCase() == 'unload'
                                        ? Icons.flag_outlined
                                        : Icons.place_outlined,
                                    size: 18,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          [
                                            if (stop.pointType.isNotEmpty)
                                              stop.pointType,
                                            stop.areaName,
                                          ].where((s) => s.isNotEmpty).join(' · '),
                                          style: GoogleFonts.poppins(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          [
                                            if (stop.reachTime != null)
                                              'Reach ${formatTripDateTime(stop.reachTime)}',
                                            if (stop.leaveTime != null)
                                              'Leave ${formatTripDateTime(stop.leaveTime)}',
                                          ].join(' · '),
                                          style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (vehicle != null) ...[
                  const SizedBox(height: 12),
                  FadeInUp(
                    delay: const Duration(milliseconds: 80),
                    child: SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('Vehicle'),
                          _metaRow('Plate', vehicle.plate),
                          if (vehicle.arrangement.isNotEmpty)
                            _metaRow('Arrangement', vehicle.arrangement),
                          _metaRow(
                            'Odometer',
                            '${vehicle.odometerStart ?? '—'} → ${vehicle.odometerEnd ?? '—'}',
                          ),
                          if (vehicle.driver != null)
                            _metaRow(
                              'Driver',
                              vehicle.driver!.name.isEmpty
                                  ? 'emp-${vehicle.driver!.employeeId}'
                                  : vehicle.driver!.name,
                            ),
                          if (vehicle.helper != null)
                            _metaRow(
                              'Helper',
                              vehicle.helper!.name.isEmpty
                                  ? 'emp-${vehicle.helper!.employeeId}'
                                  : vehicle.helper!.name,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (cargo != null &&
                    (cargo.goods != null || cargo.qty != null)) ...[
                  const SizedBox(height: 12),
                  FadeInUp(
                    delay: const Duration(milliseconds: 100),
                    child: SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('Cargo'),
                          if (cargo.goods != null)
                            _metaRow('Goods', cargo.goods!),
                          if (cargo.qty != null)
                            _metaRow(
                              'Qty',
                              [
                                cargo.qty!,
                                if (cargo.unitName != null) cargo.unitName!,
                              ].join(' '),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (customer != null &&
                    (customer.name != null || customer.phone != null)) ...[
                  const SizedBox(height: 12),
                  FadeInUp(
                    delay: const Duration(milliseconds: 120),
                    child: SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('Customer'),
                          if (customer.name != null)
                            _metaRow('Name', customer.name!),
                          if (customer.phone != null)
                            _metaRow('Phone', customer.phone!),
                          _metaRow('Bill total', moneyBdt(customer.billTotal)),
                        ],
                      ),
                    ),
                  ),
                ],
                if (trip.fuelLines.isNotEmpty || fuel != null) ...[
                  const SizedBox(height: 12),
                  FadeInUp(
                    delay: const Duration(milliseconds: 140),
                    child: SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('Fuel'),
                          if (fuel != null) ...[
                            _metaRow('Trip km', qtyFmt(fuel.tripKm)),
                            _metaRow('Consumed', qtyFmt(fuel.consumedQty)),
                            _metaRow('Fuel cost', moneyBdt(fuel.totalCost)),
                            if (fuel.avgMileage > 0)
                              _metaRow('Avg mileage', qtyFmt(fuel.avgMileage)),
                          ],
                          for (final line in trip.fuelLines)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          [
                                            line.fuelName ?? 'Fuel',
                                            if (line.fuelDate != null)
                                              formatTripDate(line.fuelDate),
                                          ].join(' · '),
                                          style: GoogleFonts.poppins(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          [
                                            '${qtyFmt(line.qty)} L',
                                            if (line.sourceType != null)
                                              line.sourceType!
                                                  .replaceAll('_', ' '),
                                            if (line.status != null)
                                              line.status!,
                                          ].join(' · '),
                                          style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    moneyBdt(line.totalAmount),
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (totals != null) ...[
                  const SizedBox(height: 12),
                  FadeInUp(
                    delay: const Duration(milliseconds: 160),
                    child: SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('Money'),
                          _metaRow(
                            'Customer bills',
                            moneyBdt(totals.customerBillAmount),
                          ),
                          _metaRow(
                            'Supplier',
                            moneyBdt(totals.supplierAmount),
                          ),
                          _metaRow(
                            'Expense',
                            moneyBdt(totals.expenseAmount),
                          ),
                          _metaRow(
                            'Advance',
                            moneyBdt(totals.advanceAmount),
                          ),
                          _metaRow(
                            'Outside fuel',
                            '${qtyFmt(totals.outSideFuelQty)} L · ${moneyBdt(totals.outSideFuelAmount)}',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (trip.advances.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  FadeInUp(
                    delay: const Duration(milliseconds: 180),
                    child: SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('Advances'),
                          for (final adv in trip.advances)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          adv.voucherNumber ?? 'Advance',
                                          style: GoogleFonts.poppins(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          [
                                            if (adv.purpose != null) adv.purpose!,
                                            if (adv.status != null) adv.status!,
                                            if (adv.issueDate != null)
                                              formatTripDate(adv.issueDate),
                                          ].join(' · '),
                                          style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    moneyBdt(adv.amount),
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (trip.note != null) ...[
                  const SizedBox(height: 12),
                  FadeInUp(
                    delay: const Duration(milliseconds: 200),
                    child: SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('Note'),
                          Text(
                            trip.note!,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _metaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
