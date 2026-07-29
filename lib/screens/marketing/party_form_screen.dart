import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../config/theme.dart';
import '../../models/marketing_models.dart';
import '../../services/auth_service.dart';
import '../../services/marketing_service.dart';
import '../../widgets/gradient_screen_header.dart';
import '../../widgets/section_card.dart';

class _ProductRow {
  final name = TextEditingController();
  final demand = TextEditingController();
  final stock = TextEditingController();
  final competitor = TextEditingController();

  void dispose() {
    name.dispose();
    demand.dispose();
    stock.dispose();
    competitor.dispose();
  }
}

class PartyFormScreen extends StatefulWidget {
  const PartyFormScreen({super.key, this.initialPartyType = 'dealer'});

  final String initialPartyType;

  @override
  State<PartyFormScreen> createState() => _PartyFormScreenState();
}

class _PartyFormScreenState extends State<PartyFormScreen> {
  final MarketingService _service = MarketingService();
  final AuthService _authService = AuthService();
  final _name = TextEditingController();
  final _tradeName = TextEditingController();
  final _contact = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  final _companyId = TextEditingController();
  final _sectorId = TextEditingController();

  String _partyType = 'dealer';
  List<Market> _markets = const [];
  int? _selectedMarketId;
  double? _lat;
  double? _lng;
  bool _loadingMarkets = true;
  bool _capturingGps = false;
  bool _submitting = false;
  final List<_ProductRow> _products = [];
  final List<XFile> _photos = [];

  @override
  void initState() {
    super.initState();
    _partyType = widget.initialPartyType;
    _products.add(_ProductRow());
    _loadMarkets();
  }

  @override
  void dispose() {
    _name.dispose();
    _tradeName.dispose();
    _contact.dispose();
    _phone.dispose();
    _address.dispose();
    _notes.dispose();
    _companyId.dispose();
    _sectorId.dispose();
    for (final p in _products) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _loadMarkets() async {
    final result = await _service.listMarkets();
    if (!mounted) return;
    setState(() {
      _markets = result.data ?? const [];
      _loadingMarkets = false;
    });
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
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return;
    setState(() => _photos.addAll(files));
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      _snack('Name is required.');
      return;
    }
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
        if (row.demand.text.trim().isNotEmpty)
          'demand_qty': double.tryParse(row.demand.text.trim()),
        if (row.stock.text.trim().isNotEmpty)
          'stock_qty': double.tryParse(row.stock.text.trim()),
        if (row.competitor.text.trim().isNotEmpty)
          'competitor_brand': row.competitor.text.trim(),
      });
    }

    final payload = <String, dynamic>{
      'party_type': _partyType,
      'name': _name.text.trim(),
      if (_tradeName.text.trim().isNotEmpty) 'trade_name': _tradeName.text.trim(),
      if (_contact.text.trim().isNotEmpty)
        'contact_person': _contact.text.trim(),
      if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
      if (_address.text.trim().isNotEmpty) 'address': _address.text.trim(),
      if (_selectedMarketId != null) 'market_id': _selectedMarketId,
      if (_companyId.text.trim().isNotEmpty)
        'company_id': int.tryParse(_companyId.text.trim()),
      if (_sectorId.text.trim().isNotEmpty)
        'sector_id': int.tryParse(_sectorId.text.trim()),
      'created_by_employee_id': employeeId,
      'owner_employee_id': employeeId,
      if (_lat != null) 'lat': _lat,
      if (_lng != null) 'lng': _lng,
      if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
      'status': 'active',
      if (products.isNotEmpty) 'products': products,
    };

    final result = await _service.createParty(payload);
    if (!mounted) return;

    if (!result.success || result.data == null) {
      setState(() => _submitting = false);
      _snack(result.message ?? 'Could not create party.');
      return;
    }

    final party = result.data!;
    if (_photos.isNotEmpty) {
      final upload = await _service.uploadAttachments(
        attachableType: 'party',
        attachableId: party.id,
        employeeId: employeeId,
        photos: _photos.map((x) => File(x.path)).toList(),
      );
      if (!upload.success) {
        _snack('Party saved, but photo upload failed: ${upload.message}');
      }
    }

    if (!mounted) return;
    setState(() => _submitting = false);
    _snack('Saved successfully.');
    Navigator.of(context).pop(party);
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
    final title = _partyType == 'farm' ? 'New Farm' : 'New Dealer';
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          GradientScreenHeader(
            title: title,
            subtitle: 'Capture identity, location & products',
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label('Party type'),
                    DropdownButtonFormField<String>(
                      initialValue: _partyType,
                      decoration: _decoration(),
                      items: const [
                        DropdownMenuItem(value: 'dealer', child: Text('Dealer')),
                        DropdownMenuItem(value: 'farm', child: Text('Farm')),
                        DropdownMenuItem(value: 'farmer', child: Text('Farmer')),
                        DropdownMenuItem(value: 'outlet', child: Text('Outlet')),
                        DropdownMenuItem(
                          value: 'prospect',
                          child: Text('Prospect'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _partyType = v);
                      },
                    ),
                    const SizedBox(height: 14),
                    _label('Name *'),
                    TextField(
                      controller: _name,
                      decoration: _decoration(hint: 'Party name'),
                    ),
                    const SizedBox(height: 14),
                    _label('Trade name'),
                    TextField(
                      controller: _tradeName,
                      decoration: _decoration(hint: 'Optional'),
                    ),
                    const SizedBox(height: 14),
                    _label('Contact person'),
                    TextField(
                      controller: _contact,
                      decoration: _decoration(),
                    ),
                    const SizedBox(height: 14),
                    _label('Phone'),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: _decoration(),
                    ),
                    const SizedBox(height: 14),
                    _label('Address'),
                    TextField(
                      controller: _address,
                      maxLines: 2,
                      decoration: _decoration(),
                    ),
                    const SizedBox(height: 14),
                    _label('Market'),
                    if (_loadingMarkets)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      DropdownButtonFormField<int?>(
                        initialValue: _selectedMarketId,
                        decoration: _decoration(hint: 'Select market'),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('None'),
                          ),
                          ..._markets.map(
                            (m) => DropdownMenuItem(
                              value: m.id,
                              child: Text(m.displayName),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() => _selectedMarketId = v),
                      ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('Company ID'),
                              TextField(
                                controller: _companyId,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: _decoration(hint: 'Optional'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('Sector ID'),
                              TextField(
                                controller: _sectorId,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: _decoration(hint: 'Optional'),
                              ),
                            ],
                          ),
                        ),
                      ],
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
                            ? 'Capture GPS'
                            : 'GPS: ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                      ),
                    ),
                    const SizedBox(height: 14),
                    _label('Notes'),
                    TextField(
                      controller: _notes,
                      maxLines: 2,
                      decoration: _decoration(),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Text(
                          'Products',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => _products.add(_ProductRow())),
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
                                      controller: row.demand,
                                      keyboardType: TextInputType.number,
                                      decoration:
                                          _decoration(hint: 'Demand'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: row.stock,
                                      keyboardType: TextInputType.number,
                                      decoration: _decoration(hint: 'Stock'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: row.competitor,
                                decoration:
                                    _decoration(hint: 'Competitor brand'),
                              ),
                              if (_products.length > 1)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: IconButton(
                                    onPressed: () {
                                      setState(() {
                                        row.dispose();
                                        _products.removeAt(i);
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: AppColors.error,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    Text(
                      'Photos',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ..._photos.asMap().entries.map((e) {
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(
                                  File(e.value.path),
                                  width: 72,
                                  height: 72,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: () => setState(
                                    () => _photos.removeAt(e.key),
                                  ),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: AppColors.error,
                                      shape: BoxShape.circle,
                                    ),
                                    padding: const EdgeInsets.all(2),
                                    child: const Icon(
                                      Icons.close,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }),
                        OutlinedButton(
                          onPressed: _pickPhotos,
                          child: const Text('Add photos'),
                        ),
                      ],
                    ),
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
                                'Submit',
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
