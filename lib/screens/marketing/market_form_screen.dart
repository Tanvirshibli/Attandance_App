import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/theme.dart';
import '../../data/marketing_demo_masters.dart';
import '../../models/booking_form_data_models.dart';
import '../../services/marketing_service.dart';
import '../../services/sales_service.dart';
import '../../utils/marketing_location_helper.dart';
import '../../widgets/gradient_screen_header.dart';
import '../../widgets/searchable_select_field.dart';
import '../../widgets/section_card.dart';

class MarketFormScreen extends StatefulWidget {
  const MarketFormScreen({super.key});

  @override
  State<MarketFormScreen> createState() => _MarketFormScreenState();
}

class _MarketFormScreenState extends State<MarketFormScreen> {
  final MarketingService _service = MarketingService();
  final SalesService _salesService = SalesService();
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _division = TextEditingController();
  final _district = TextEditingController();
  final _upazila = TextEditingController();
  final _union = TextEditingController();
  final _village = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();

  List<BookingFormCompany> _companies = MarketingDemoMasters.companies;
  List<BookingFormSector> _sectors = MarketingDemoMasters.sectors;
  BookingFormCompany? _company;
  BookingFormSector? _sector;
  String _status = 'active';
  double? _lat;
  double? _lng;
  bool _resolvingLocation = true;
  String? _locationStatus;
  bool _submitting = false;
  bool _loadingMasters = true;

  List<BookingFormSector> get _sectorsForCompany {
    if (_company == null) return _sectors;
    final filtered =
        _sectors.where((s) => s.companyId == _company!.id).toList();
    return filtered.isNotEmpty ? filtered : _sectors;
  }

  @override
  void initState() {
    super.initState();
    _autoFillLocation();
    _loadMasters();
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _division.dispose();
    _district.dispose();
    _upazila.dispose();
    _union.dispose();
    _village.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadMasters() async {
    final result = await _salesService.fetchBookingFormData();
    if (!mounted) return;
    setState(() {
      _loadingMasters = false;
      if (result.success && result.data != null) {
        _companies = MarketingDemoMasters.companiesOr(result.data!.companies);
        _sectors = MarketingDemoMasters.sectorsOr(result.data!.sectors);
      }
    });
  }

  Future<void> _autoFillLocation() async {
    setState(() {
      _resolvingLocation = true;
      _locationStatus = 'Detecting location…';
    });
    try {
      final snap = await MarketingLocationHelper.capture();
      if (!mounted) return;
      if (snap == null) {
        setState(() {
          _resolvingLocation = false;
          _locationStatus =
              'Location unavailable — fill geo fields manually.';
        });
        return;
      }
      setState(() {
        _lat = snap.latitude;
        _lng = snap.longitude;
        if (_division.text.trim().isEmpty && snap.division != null) {
          _division.text = snap.division!;
        }
        if (_district.text.trim().isEmpty && snap.district != null) {
          _district.text = snap.district!;
        }
        if (_upazila.text.trim().isEmpty && snap.upazila != null) {
          _upazila.text = snap.upazila!;
        }
        if (_union.text.trim().isEmpty && snap.unionName != null) {
          _union.text = snap.unionName!;
        }
        if (_village.text.trim().isEmpty && snap.village != null) {
          _village.text = snap.village!;
        }
        if (_address.text.trim().isEmpty && snap.address != null) {
          _address.text = snap.address!;
        }
        _resolvingLocation = false;
        _locationStatus =
            'Location filled — edit if needed (${snap.latitude.toStringAsFixed(5)}, ${snap.longitude.toStringAsFixed(5)})';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resolvingLocation = false;
        _locationStatus = 'Location failed — fill geo fields manually.';
      });
      _snack('Could not get location: $e');
    }
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      _snack('Market name is required.');
      return;
    }
    if (_lat == null || _lng == null) {
      final snap = await MarketingLocationHelper.capture();
      if (snap != null) {
        _lat = snap.latitude;
        _lng = snap.longitude;
      }
    }
    setState(() => _submitting = true);
    final result = await _service.createMarket(
      name: _name.text.trim(),
      code: _code.text.trim().isEmpty ? null : _code.text.trim(),
      companyId: _company?.id,
      sectorId: _sector?.id,
      divisionName:
          _division.text.trim().isEmpty ? null : _division.text.trim(),
      district: _district.text.trim().isEmpty ? null : _district.text.trim(),
      upazila: _upazila.text.trim().isEmpty ? null : _upazila.text.trim(),
      unionName: _union.text.trim().isEmpty ? null : _union.text.trim(),
      villageName: _village.text.trim().isEmpty ? null : _village.text.trim(),
      address: _address.text.trim().isEmpty ? null : _address.text.trim(),
      lat: _lat,
      lng: _lng,
      status: _status,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!result.success || result.data == null) {
      _snack(result.message ?? 'Could not create market.');
      return;
    }
    _snack('Market saved.');
    Navigator.of(context).pop(result.data);
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
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
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
          const GradientScreenHeader(
            title: 'New Market',
            subtitle: 'Location & geo hierarchy',
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              child: Column(
                children: [
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionTitle('Identity'),
                        _label('Name *'),
                        TextField(
                          controller: _name,
                          decoration: _decoration(hint: 'Market name'),
                        ),
                        const SizedBox(height: 12),
                        _label('Code'),
                        TextField(
                          controller: _code,
                          decoration: _decoration(hint: 'Optional'),
                        ),
                        const SizedBox(height: 12),
                        if (_loadingMasters)
                          const LinearProgressIndicator()
                        else ...[
                          SearchableSelectField<BookingFormCompany>(
                            label: 'Company',
                            icon: Icons.apartment_outlined,
                            options: _companies,
                            selected: _company,
                            displayString: (c) => c.displayName,
                            searchText: (c) => c.displayName.toLowerCase(),
                            onSelected: (c) => setState(() {
                              _company = c;
                              if (_sector != null &&
                                  c != null &&
                                  _sector!.companyId != null &&
                                  _sector!.companyId != c.id) {
                                _sector = null;
                              }
                            }),
                          ),
                          const SizedBox(height: 12),
                          SearchableSelectField<BookingFormSector>(
                            label: 'Sector',
                            icon: Icons.hub_outlined,
                            options: _sectorsForCompany,
                            selected: _sector,
                            displayString: (s) => s.name,
                            searchText: (s) => s.searchText,
                            onSelected: (s) => setState(() => _sector = s),
                          ),
                        ],
                        const SizedBox(height: 12),
                        _label('Status'),
                        DropdownButtonFormField<String>(
                          initialValue: _status,
                          decoration: _decoration(),
                          items: const [
                            DropdownMenuItem(
                              value: 'active',
                              child: Text('Active'),
                            ),
                            DropdownMenuItem(
                              value: 'inactive',
                              child: Text('Inactive'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _status = v);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionTitle('Location'),
                        if (_locationStatus != null) ...[
                          Text(
                            _locationStatus!,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: _resolvingLocation
                                  ? AppColors.textHint
                                  : AppColors.textSecondary,
                            ),
                          ),
                          if (_resolvingLocation) ...[
                            const SizedBox(height: 8),
                            const LinearProgressIndicator(),
                          ],
                          const SizedBox(height: 12),
                        ],
                        _label('Division'),
                        TextField(
                          controller: _division,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('District'),
                        TextField(
                          controller: _district,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Upazila'),
                        TextField(
                          controller: _upazila,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Union'),
                        TextField(
                          controller: _union,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Village'),
                        TextField(
                          controller: _village,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Address'),
                        TextField(
                          controller: _address,
                          maxLines: 2,
                          decoration: _decoration(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionTitle('Notes'),
                        TextField(
                          controller: _notes,
                          maxLines: 2,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 20),
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
                                    'Save market',
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
