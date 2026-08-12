import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/theme.dart';
import '../../models/marketing_models.dart';
import '../../services/auth_service.dart';
import '../../services/marketing_service.dart';
import '../../services/sales_service.dart';
import '../../utils/marketing_location_helper.dart';
import '../../widgets/gradient_screen_header.dart';
import '../../widgets/section_card.dart';

class _ProductRow {
  final name = TextEditingController();
  final demand = TextEditingController();
  final stock = TextEditingController();
  final competitor = TextEditingController();
  String relationType = 'stock';

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
  final SalesService _salesService = SalesService();
  final _name = TextEditingController();
  final _tradeName = TextEditingController();
  final _contact = TextEditingController();
  final _phone = TextEditingController();
  final _altPhone = TextEditingController();
  final _email = TextEditingController();
  final _nid = TextEditingController();
  final _tradeLicense = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  final _farmType = TextEditingController();
  final _capacity = TextEditingController();
  final _creditLimit = TextEditingController();

  String _partyType = 'dealer';
  String _paymentMode = 'cash';
  String _leadStatus = 'new';
  List<Market> _markets = const [];
  List<Party> _dealers = const [];
  List<BookingFormCompany> _companies = const [];
  List<BookingFormSector> _sectors = const [];
  int? _selectedMarketId;
  int? _parentPartyId;
  int? _selectedCompanyId;
  int? _selectedSectorId;
  double? _lat;
  double? _lng;
  bool _loadingMarkets = true;
  bool _loadingDealers = false;
  bool _loadingMasters = true;
  bool _resolvingLocation = true;
  String? _locationStatus;
  bool _submitting = false;
  final List<_ProductRow> _products = [];
  final List<XFile> _photos = [];

  static const _relationTypes = ['stock', 'demand', 'sells', 'uses', 'competitor'];
  static const _paymentModes = ['cash', 'credit', 'mixed', 'other'];
  static const _leadStatuses = ['new', 'warm', 'hot', 'converted', 'lost'];

  bool get _isFarm =>
      _partyType == 'farm' || _partyType == 'farmer';

  List<BookingFormSector> get _sectorsForCompany =>
      _sectors.where((s) => s.companyId == _selectedCompanyId).toList();

  @override
  void initState() {
    super.initState();
    _partyType = widget.initialPartyType;
    _products.add(_ProductRow());
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _loadMarkets(),
      _loadFormMasters(),
      _autoFillLocation(),
      if (_isFarm) _loadDealers(),
    ]);
  }

  @override
  void dispose() {
    _name.dispose();
    _tradeName.dispose();
    _contact.dispose();
    _phone.dispose();
    _altPhone.dispose();
    _email.dispose();
    _nid.dispose();
    _tradeLicense.dispose();
    _address.dispose();
    _notes.dispose();
    _farmType.dispose();
    _capacity.dispose();
    _creditLimit.dispose();
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

  Future<void> _loadFormMasters() async {
    final result = await _salesService.fetchBookingFormData();
    if (!mounted) return;
    setState(() {
      _loadingMasters = false;
      if (result.success && result.data != null) {
        _companies = result.data!.companies;
        _sectors = result.data!.sectors;
      } else if (result.message != null) {
        _snack(result.message!);
      }
    });
  }

  Future<void> _loadDealers() async {
    setState(() => _loadingDealers = true);
    final profile = await _authService.getCurrentUserProfile();
    final result = await _service.listParties(
      employeeId: profile?.canonicalEmployeeId,
      partyType: 'dealer',
    );
    if (!mounted) return;
    setState(() {
      _dealers = result.data ?? const [];
      _loadingDealers = false;
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
          _locationStatus = 'Location unavailable — enter address manually.';
        });
        return;
      }
      setState(() {
        _lat = snap.latitude;
        _lng = snap.longitude;
        if (_address.text.trim().isEmpty &&
            snap.address != null &&
            snap.address!.isNotEmpty) {
          _address.text = snap.address!;
        }
        _resolvingLocation = false;
        _locationStatus =
            'Location filled — edit address if needed (${snap.latitude.toStringAsFixed(5)}, ${snap.longitude.toStringAsFixed(5)})';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resolvingLocation = false;
        _locationStatus = 'Location failed — enter address manually.';
      });
      _snack('Could not get location: $e');
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

    if (_lat == null || _lng == null) {
      final snap = await MarketingLocationHelper.capture();
      if (snap != null) {
        _lat = snap.latitude;
        _lng = snap.longitude;
        if (_address.text.trim().isEmpty && snap.address != null) {
          _address.text = snap.address!;
        }
      }
    }

    setState(() => _submitting = true);

    final products = <Map<String, dynamic>>[];
    for (final row in _products) {
      final name = row.name.text.trim();
      if (name.isEmpty) continue;
      products.add({
        'product_name': name,
        'relation_type': row.relationType,
        if (row.demand.text.trim().isNotEmpty)
          'demand_qty': double.tryParse(row.demand.text.trim()),
        if (row.stock.text.trim().isNotEmpty)
          'stock_qty': double.tryParse(row.stock.text.trim()),
        if (row.competitor.text.trim().isNotEmpty)
          'competitor_company': row.competitor.text.trim(),
      });
    }

    final payload = <String, dynamic>{
      'employee_id': employeeId,
      'party_type': _partyType,
      'name': _name.text.trim(),
      if (_tradeName.text.trim().isNotEmpty) 'trade_name': _tradeName.text.trim(),
      if (_contact.text.trim().isNotEmpty)
        'contact_person': _contact.text.trim(),
      if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
      if (_altPhone.text.trim().isNotEmpty) 'alt_phone': _altPhone.text.trim(),
      if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
      if (_nid.text.trim().isNotEmpty) 'nid_no': _nid.text.trim(),
      if (_tradeLicense.text.trim().isNotEmpty)
        'trade_license_no': _tradeLicense.text.trim(),
      if (_address.text.trim().isNotEmpty) 'address': _address.text.trim(),
      if (_selectedMarketId != null) 'market_id': _selectedMarketId,
      if (_isFarm && _parentPartyId != null) 'parent_party_id': _parentPartyId,
      if (_selectedCompanyId != null) 'company_id': _selectedCompanyId,
      if (_selectedSectorId != null) 'sector_id': _selectedSectorId,
      if (_isFarm && _farmType.text.trim().isNotEmpty)
        'farm_type': _farmType.text.trim(),
      if (_isFarm && _capacity.text.trim().isNotEmpty)
        'capacity': double.tryParse(_capacity.text.trim()),
      if (_creditLimit.text.trim().isNotEmpty)
        'credit_limit': double.tryParse(_creditLimit.text.trim()),
      'payment_mode': _paymentMode,
      'lead_status': _leadStatus,
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

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _isFarm ? 'New Farm' : 'New Dealer';
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          GradientScreenHeader(
            title: title,
            subtitle: 'Identity, contact, credit & products',
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                children: [
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionTitle('Basic'),
                        _label('Party type'),
                        DropdownButtonFormField<String>(
                          initialValue: _partyType,
                          decoration: _decoration(),
                          items: const [
                            DropdownMenuItem(
                              value: 'dealer',
                              child: Text('Dealer'),
                            ),
                            DropdownMenuItem(
                              value: 'farm',
                              child: Text('Farm'),
                            ),
                            DropdownMenuItem(
                              value: 'farmer',
                              child: Text('Farmer'),
                            ),
                            DropdownMenuItem(
                              value: 'outlet',
                              child: Text('Outlet'),
                            ),
                            DropdownMenuItem(
                              value: 'prospect',
                              child: Text('Prospect'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _partyType = v;
                              if (_isFarm && _dealers.isEmpty) {
                                _loadDealers();
                              }
                              if (!_isFarm) _parentPartyId = null;
                            });
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
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _label('Company'),
                                  if (_loadingMasters)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 12),
                                      child: LinearProgressIndicator(),
                                    )
                                  else
                                    DropdownButtonFormField<int?>(
                                      initialValue: _selectedCompanyId,
                                      isExpanded: true,
                                      decoration: _decoration(hint: 'Optional'),
                                      items: [
                                        const DropdownMenuItem<int?>(
                                          value: null,
                                          child: Text('None'),
                                        ),
                                        ..._companies.map(
                                          (c) => DropdownMenuItem(
                                            value: c.id,
                                            child: Text(
                                              c.displayName,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                      ],
                                      onChanged: (v) => setState(() {
                                        _selectedCompanyId = v;
                                        _selectedSectorId = null;
                                      }),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _label('Sector'),
                                  if (_loadingMasters)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 12),
                                      child: LinearProgressIndicator(),
                                    )
                                  else
                                    DropdownButtonFormField<int?>(
                                      initialValue: _selectedSectorId,
                                      isExpanded: true,
                                      decoration: _decoration(
                                        hint: _sectorsForCompany.isEmpty
                                            ? 'No sectors'
                                            : 'Optional',
                                      ),
                                      items: [
                                        const DropdownMenuItem<int?>(
                                          value: null,
                                          child: Text('None'),
                                        ),
                                        ..._sectorsForCompany.map(
                                          (s) => DropdownMenuItem(
                                            value: s.id,
                                            child: Text(
                                              s.name,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                      ],
                                      onChanged: _sectorsForCompany.isEmpty
                                          ? null
                                          : (v) => setState(
                                                () => _selectedSectorId = v,
                                              ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionTitle('Contact'),
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
                        _label('Alt phone'),
                        TextField(
                          controller: _altPhone,
                          keyboardType: TextInputType.phone,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 14),
                        _label('Email'),
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 14),
                        _label('NID'),
                        TextField(
                          controller: _nid,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 14),
                        _label('Trade license'),
                        TextField(
                          controller: _tradeLicense,
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
                        _sectionTitle('Farm & Credit'),
                        if (_isFarm) ...[
                          _label('Parent dealer'),
                          if (_loadingDealers)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else
                            DropdownButtonFormField<int?>(
                              initialValue: _parentPartyId,
                              decoration: _decoration(hint: 'Link dealer'),
                              items: [
                                const DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text('None'),
                                ),
                                ..._dealers.map(
                                  (d) => DropdownMenuItem(
                                    value: d.id,
                                    child: Text(d.displayName),
                                  ),
                                ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _parentPartyId = v),
                            ),
                          const SizedBox(height: 14),
                          _label('Farm type'),
                          TextField(
                            controller: _farmType,
                            decoration:
                                _decoration(hint: 'e.g. Broiler, Layer'),
                          ),
                          const SizedBox(height: 14),
                          _label('Capacity'),
                          TextField(
                            controller: _capacity,
                            keyboardType: TextInputType.number,
                            decoration: _decoration(),
                          ),
                          const SizedBox(height: 14),
                        ],
                        _label('Credit limit'),
                        TextField(
                          controller: _creditLimit,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 14),
                        _label('Payment mode'),
                        DropdownButtonFormField<String>(
                          initialValue: _paymentMode,
                          decoration: _decoration(),
                          items: _paymentModes
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(p),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _paymentMode = v);
                          },
                        ),
                        const SizedBox(height: 14),
                        _label('Lead status'),
                        DropdownButtonFormField<String>(
                          initialValue: _leadStatus,
                          decoration: _decoration(),
                          items: _leadStatuses
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(p),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _leadStatus = v);
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
                            onChanged: (v) =>
                                setState(() => _selectedMarketId = v),
                          ),
                        const SizedBox(height: 14),
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
                          const SizedBox(height: 14),
                        ],
                        _label('Notes'),
                        TextField(
                          controller: _notes,
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
                        Row(
                          children: [
                            Expanded(child: _sectionTitle('Products')),
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
                                  DropdownButtonFormField<String>(
                                    initialValue: row.relationType,
                                    decoration:
                                        _decoration(hint: 'Relation type'),
                                    items: _relationTypes
                                        .map(
                                          (t) => DropdownMenuItem(
                                            value: t,
                                            child: Text(t),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) {
                                      if (v != null) {
                                        setState(() => row.relationType = v);
                                      }
                                    },
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
                                          decoration:
                                              _decoration(hint: 'Stock'),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: row.competitor,
                                    decoration: _decoration(
                                      hint: 'Competitor company',
                                    ),
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
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionTitle('Photos'),
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
