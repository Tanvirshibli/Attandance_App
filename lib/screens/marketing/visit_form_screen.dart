import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../config/theme.dart';
import '../../models/marketing_models.dart';
import '../../services/auth_service.dart';
import '../../services/marketing_service.dart';
import '../../widgets/gradient_screen_header.dart';
import '../../widgets/section_card.dart';

class _ObsRow {
  final name = TextEditingController();
  final stock = TextEditingController();
  final order = TextEditingController();
  final price = TextEditingController();

  void dispose() {
    name.dispose();
    stock.dispose();
    order.dispose();
    price.dispose();
  }
}

class VisitFormScreen extends StatefulWidget {
  const VisitFormScreen({super.key, required this.party});

  final Party party;

  @override
  State<VisitFormScreen> createState() => _VisitFormScreenState();
}

class _VisitFormScreenState extends State<VisitFormScreen> {
  final MarketingService _service = MarketingService();
  final AuthService _authService = AuthService();
  final _purpose = TextEditingController();
  final _outcome = TextEditingController();
  final _notes = TextEditingController();

  double? _lat;
  double? _lng;
  bool _capturingGps = false;
  bool _submitting = false;
  final List<_ObsRow> _products = [_ObsRow()];
  final List<XFile> _photos = [];

  @override
  void dispose() {
    _purpose.dispose();
    _outcome.dispose();
    _notes.dispose();
    for (final p in _products) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _captureGps() async {
    setState(() => _capturingGps = true);
    try {
      final status = await Permission.locationWhenInUse.request();
      if (!status.isGranted) {
        _snack('Location permission required.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
    } catch (e) {
      _snack('Could not get GPS: $e');
    } finally {
      if (mounted) setState(() => _capturingGps = false);
    }
  }

  Future<void> _pickPhotos() async {
    final files = await ImagePicker().pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return;
    setState(() => _photos.addAll(files));
  }

  Future<void> _submit() async {
    final profile = await _authService.getCurrentUserProfile();
    final employeeId = profile?.canonicalEmployeeId;
    if (employeeId == null || employeeId <= 0) {
      _snack('Employee profile not linked.');
      return;
    }

    setState(() => _submitting = true);
    final products = <Map<String, dynamic>>[];
    for (final row in _products) {
      final name = row.name.text.trim();
      if (name.isEmpty) continue;
      products.add({
        'product_name': name,
        if (row.stock.text.trim().isNotEmpty)
          'observed_stock': double.tryParse(row.stock.text.trim()),
        if (row.order.text.trim().isNotEmpty)
          'order_qty': double.tryParse(row.order.text.trim()),
        if (row.price.text.trim().isNotEmpty)
          'price': double.tryParse(row.price.text.trim()),
      });
    }

    final now = DateTime.now();
    final payload = <String, dynamic>{
      'party_id': widget.party.id,
      'employee_id': employeeId,
      'visit_date': DateFormat('yyyy-MM-dd').format(now),
      'check_in_at': now.toIso8601String(),
      if (_lat != null) 'check_in_lat': _lat,
      if (_lng != null) 'check_in_lng': _lng,
      if (_purpose.text.trim().isNotEmpty) 'purpose': _purpose.text.trim(),
      if (_outcome.text.trim().isNotEmpty) 'outcome': _outcome.text.trim(),
      if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
      'status': 'completed',
      if (products.isNotEmpty) 'products': products,
    };

    final result = await _service.createVisit(payload);
    if (!mounted) return;
    if (!result.success || result.data == null) {
      setState(() => _submitting = false);
      _snack(result.message ?? 'Could not save visit.');
      return;
    }

    final visit = result.data!;
    if (_photos.isNotEmpty) {
      await _service.uploadAttachments(
        attachableType: 'visit',
        attachableId: visit.id,
        employeeId: employeeId,
        photos: _photos.map((x) => File(x.path)).toList(),
      );
    }

    if (!mounted) return;
    setState(() => _submitting = false);
    _snack('Visit saved.');
    Navigator.of(context).pop(visit);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  InputDecoration _decoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          GradientScreenHeader(
            title: 'New Visit',
            subtitle: widget.party.displayName,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label('Purpose'),
                    TextField(
                      controller: _purpose,
                      decoration: _decoration(hint: 'e.g. Stock check'),
                    ),
                    const SizedBox(height: 14),
                    _label('Outcome'),
                    TextField(
                      controller: _outcome,
                      decoration: _decoration(hint: 'e.g. Order promised'),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _capturingGps ? null : _captureGps,
                      icon: _capturingGps
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location_outlined),
                      label: Text(
                        _lat == null
                            ? 'Check-in GPS'
                            : 'Check-in: ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                      ),
                    ),
                    const SizedBox(height: 14),
                    _label('Notes'),
                    TextField(
                      controller: _notes,
                      maxLines: 2,
                      decoration: _decoration(),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          'Product observations',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => _products.add(_ObsRow())),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add'),
                        ),
                      ],
                    ),
                    ...List.generate(_products.length, (i) {
                      final row = _products[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              TextField(
                                controller: row.name,
                                decoration:
                                    _decoration(hint: 'Product name'),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: row.stock,
                                      keyboardType: TextInputType.number,
                                      decoration:
                                          _decoration(hint: 'Stock'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: row.order,
                                      keyboardType: TextInputType.number,
                                      decoration:
                                          _decoration(hint: 'Order qty'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: row.price,
                                      keyboardType: TextInputType.number,
                                      decoration:
                                          _decoration(hint: 'Price'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _pickPhotos,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(
                        _photos.isEmpty
                            ? 'Add photos'
                            : '${_photos.length} photo(s)',
                      ),
                    ),
                    if (_photos.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 72,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _photos.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, i) => Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(
                                  File(_photos[i].path),
                                  width: 72,
                                  height: 72,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _photos.removeAt(i)),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: AppColors.error,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Submit visit',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
