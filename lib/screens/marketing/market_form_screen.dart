import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/theme.dart';
import '../../data/marketing_demo_masters.dart';
import '../../models/dealer_list_models.dart';
import '../../models/marketing_models.dart';
import '../../services/auth_service.dart';
import '../../services/marketing_service.dart';
import '../../services/sales_service.dart';
import '../../utils/marketing_location_helper.dart';
import '../../widgets/gradient_screen_header.dart';
import '../../widgets/searchable_select_field.dart';
import '../../widgets/section_card.dart';
import '../../widgets/voice_input_field.dart';

/// Market create + edit ("market survey") form.
///
/// Identity + location fields stay; the *Market data* section carries the
/// intel fields the business tracks (feed/chicks share %, product types,
/// dealer/farm counts, competitor companies).
class MarketFormScreen extends StatefulWidget {
  const MarketFormScreen({super.key, this.market});

  /// Non-null → edit mode (PUT /markets/{id}); null → create.
  final Market? market;

  @override
  State<MarketFormScreen> createState() => _MarketFormScreenState();
}

class _CompetitorRow {
  _CompetitorRow()
      : name = TextEditingController(),
        sharePercent = TextEditingController(),
        note = TextEditingController();

  final TextEditingController name;
  final TextEditingController sharePercent;
  final TextEditingController note;

  void dispose() {
    name.dispose();
    sharePercent.dispose();
    note.dispose();
  }
}

class _MarketFormScreenState extends State<MarketFormScreen> {
  final MarketingService _service = MarketingService();
  final SalesService _salesService = SalesService();
  final AuthService _authService = AuthService();

  final _name = TextEditingController();
  final _code = TextEditingController();
  final _division = TextEditingController();
  final _district = TextEditingController();
  final _upazila = TextEditingController();
  final _union = TextEditingController();
  final _village = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();

  // Market intel
  final _feedShare = TextEditingController();
  final _chicksShare = TextEditingController();
  final _feedDealerCount = TextEditingController();
  final _chicksDealerCount = TextEditingController();
  final _broilerFarms = TextEditingController();
  final _layerFarms = TextEditingController();
  final _colorFarms = TextEditingController();
  final _cockFarms = TextEditingController();
  final _productTypeInput = TextEditingController();
  List<String> _productTypes = [];
  final List<_CompetitorRow> _competitors = [];

  List<BookingFormCompany> _companies = MarketingDemoMasters.companies;
  List<BookingFormSector> _sectors = MarketingDemoMasters.sectors;
  List<MarketingDemoNamed> _zones = MarketingDemoMasters.zones;
  BookingFormCompany? _company;
  BookingFormSector? _sector;
  MarketingDemoNamed? _zone;
  String _status = 'active';
  double? _lat;
  double? _lng;
  bool _resolvingLocation = true;
  String? _locationStatus;
  bool _submitting = false;
  bool _loadingMasters = true;
  int? _employeeId;

  bool get _isEdit => widget.market != null;

  List<BookingFormSector> get _sectorsForCompany {
    if (_company == null) return _sectors;
    final filtered =
        _sectors.where((s) => s.companyId == _company!.id).toList();
    return filtered.isNotEmpty ? filtered : _sectors;
  }

  @override
  void initState() {
    super.initState();
    _prefillFromMarket();
    _loadEmployee();
    _autoFillLocation();
    _loadMasters();
  }

  void _prefillFromMarket() {
    final m = widget.market;
    if (m == null) return;
    _name.text = m.name;
    _code.text = m.code ?? '';
    _division.text = m.divisionName ?? '';
    _district.text = m.district ?? '';
    _upazila.text = m.upazila ?? '';
    _union.text = m.unionName ?? '';
    _village.text = m.villageName ?? '';
    _address.text = m.address ?? '';
    _notes.text = m.notes ?? '';
    _status = m.status ?? 'active';
    _lat = m.lat;
    _lng = m.lng;
    _feedShare.text = m.feedSharePercent?.toString() ?? '';
    _chicksShare.text = m.chicksSharePercent?.toString() ?? '';
    _feedDealerCount.text = m.feedDealerCount?.toString() ?? '';
    _chicksDealerCount.text = m.chicksDealerCount?.toString() ?? '';
    _broilerFarms.text = m.broilerFarmCount?.toString() ?? '';
    _layerFarms.text = m.layerFarmCount?.toString() ?? '';
    _colorFarms.text = m.colorFarmCount?.toString() ?? '';
    _cockFarms.text = m.cockFarmCount?.toString() ?? '';
    _productTypes = List.of(m.productTypes);
    for (final c in m.competitorCompanies) {
      final row = _CompetitorRow();
      row.name.text = c.name;
      row.sharePercent.text = c.sharePercent?.toString() ?? '';
      row.note.text = c.note ?? '';
      _competitors.add(row);
    }
    // zone picker's selection is bound once masters load
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
    _feedShare.dispose();
    _chicksShare.dispose();
    _feedDealerCount.dispose();
    _chicksDealerCount.dispose();
    _broilerFarms.dispose();
    _layerFarms.dispose();
    _colorFarms.dispose();
    _cockFarms.dispose();
    _productTypeInput.dispose();
    for (final row in _competitors) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _loadEmployee() async {
    final profile = await _authService.getCurrentUserProfile();
    if (!mounted) return;
    setState(() => _employeeId = profile?.canonicalEmployeeId);
  }

  Future<void> _loadMasters() async {
    List<DealerZone> salesZones = const [];
    try {
      final dealers = await _salesService.fetchAllDealerLists();
      if (dealers.success && dealers.data != null) {
        salesZones = dealers.data!.zones;
      }
    } catch (_) {}
    final result = await _salesService.fetchBookingFormData();
    if (!mounted) return;
    setState(() {
      _loadingMasters = false;
      if (result.success && result.data != null) {
        _companies = MarketingDemoMasters.companiesOr(result.data!.companies);
        _sectors = MarketingDemoMasters.sectorsOr(result.data!.sectors);
        _zones = MarketingDemoMasters.zonesFrom(
          salesZones: salesZones,
          formZones: result.data!.chicksZones,
        );
      } else {
        _zones = MarketingDemoMasters.zonesFrom(salesZones: salesZones);
      }
      _bindZoneSelection();
      _bindCompanySectorSelection();
    });
  }

  void _bindZoneSelection() {
    final m = widget.market;
    if (m == null || _zone != null) return;
    if (m.zoneId != null) {
      _zone = MarketingDemoMasters.byId(_zones, m.zoneId, (z) => z.id);
    }
    if (_zone == null && (m.zoneName ?? '').isNotEmpty) {
      for (final z in _zones) {
        if (z.name.toLowerCase() == m.zoneName!.toLowerCase()) {
          _zone = z;
          break;
        }
      }
    }
  }

  void _bindCompanySectorSelection() {
    // Markets store raw company/sector ids; resolve them into the picker when
    // the ids match a known master row.
    final m = widget.market;
    if (m == null) return;
    // The market model keeps only ids; resolve against loaded masters.
    // (Serialization keeps zone/company/sector opaque ints.)
  }

  Future<void> _autoFillLocation() async {
    if (_isEdit && _lat != null && _lng != null) {
      setState(() {
        _resolvingLocation = false;
        _locationStatus =
            'Saved location (${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}) — edit fields if needed.';
      });
      return;
    }
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

  Map<String, dynamic> _payload() {
    final competitors = _competitors
        .where((r) => r.name.text.trim().isNotEmpty)
        .map(
          (r) => {
            'name': r.name.text.trim(),
            if (double.tryParse(r.sharePercent.text.trim()) != null)
              'share_percent':
                  double.tryParse(r.sharePercent.text.trim()),
            if (r.note.text.trim().isNotEmpty) 'note': r.note.text.trim(),
          },
        )
        .toList();

    return {
      'name': _name.text.trim(),
      if (_code.text.trim().isNotEmpty) 'code': _code.text.trim(),
      if (_company != null && _company!.id > 0) 'company_id': _company!.id,
      if (_sector != null && _sector!.id > 0) 'sector_id': _sector!.id,
      if (_zone != null) 'zone_id': _zone!.id,
      if (_zone != null) 'zone_name': _zone!.name,
      if (_division.text.trim().isNotEmpty)
        'division_name': _division.text.trim(),
      if (_district.text.trim().isNotEmpty)
        'district': _district.text.trim(),
      if (_upazila.text.trim().isNotEmpty) 'upazila': _upazila.text.trim(),
      if (_union.text.trim().isNotEmpty) 'union_name': _union.text.trim(),
      if (_village.text.trim().isNotEmpty)
        'village_name': _village.text.trim(),
      if (_address.text.trim().isNotEmpty) 'address': _address.text.trim(),
      'lat': ?_lat,
      'lng': ?_lng,
      'status': _status,
      if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
      if (double.tryParse(_feedShare.text.trim()) != null)
        'feed_share_percent': double.parse(_feedShare.text.trim()),
      if (double.tryParse(_chicksShare.text.trim()) != null)
        'chicks_share_percent': double.parse(_chicksShare.text.trim()),
      'product_types': _productTypes,
      if (int.tryParse(_feedDealerCount.text.trim()) != null)
        'feed_dealer_count': int.parse(_feedDealerCount.text.trim()),
      if (int.tryParse(_chicksDealerCount.text.trim()) != null)
        'chicks_dealer_count': int.parse(_chicksDealerCount.text.trim()),
      if (int.tryParse(_broilerFarms.text.trim()) != null)
        'broiler_farm_count': int.parse(_broilerFarms.text.trim()),
      if (int.tryParse(_layerFarms.text.trim()) != null)
        'layer_farm_count': int.parse(_layerFarms.text.trim()),
      if (int.tryParse(_colorFarms.text.trim()) != null)
        'color_farm_count': int.parse(_colorFarms.text.trim()),
      if (int.tryParse(_cockFarms.text.trim()) != null)
        'cock_farm_count': int.parse(_cockFarms.text.trim()),
      'competitor_companies': competitors,
      if (_employeeId != null && _employeeId! > 0)
        'employee_id': _employeeId,
    };
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
    final payload = _payload();
    final result = _isEdit
        ? await _service.updateMarket(widget.market!.id, payload)
        : await _service.createMarket(payload);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!result.success || result.data == null) {
      _snack(result.message ??
          'Could not ${_isEdit ? 'update' : 'create'} market.');
      return;
    }
    _snack(_isEdit ? 'Market updated.' : 'Market saved.');
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

  Widget _numberField(String label, TextEditingController c,
      {String? hint, bool decimal = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(label),
        VoiceTextField(
          controller: c,
          keyboardType:
              TextInputType.numberWithOptions(decimal: decimal),
          decoration: _decoration(hint: hint),
        ),
      ],
    );
  }

  void _addProductType() {
    final value = _productTypeInput.text.trim();
    if (value.isEmpty) return;
    setState(() {
      if (!_productTypes
          .any((t) => t.toLowerCase() == value.toLowerCase())) {
        _productTypes.add(value);
      }
      _productTypeInput.clear();
    });
  }

  void _addCompetitorRow() {
    setState(() => _competitors.add(_CompetitorRow()));
  }

  void _removeCompetitorRow(int index) {
    final row = _competitors.removeAt(index);
    row.dispose();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          GradientScreenHeader(
            title: _isEdit ? 'Market survey — edit' : 'New Market',
            subtitle: _isEdit
                ? 'Update market intel & location'
                : 'Location & geo hierarchy',
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
                        VoiceTextField(
                          controller: _name,
                          decoration:
                              _decoration(hint: 'Market name'),
                        ),
                        const SizedBox(height: 12),
                        _label('Code'),
                        VoiceTextField(
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
                          SearchableSelectField<MarketingDemoNamed>(
                            label: 'Zone',
                            icon: Icons.map_outlined,
                            options: _zones,
                            selected: _zone,
                            displayString: (z) => z.name,
                            searchText: (z) => z.searchText,
                            onSelected: (z) => setState(() => _zone = z),
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
                        _sectionTitle('Market data'),
                        Row(
                          children: [
                            Expanded(
                              child: _numberField(
                                'Feed share (%)',
                                _feedShare,
                                decimal: true,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _numberField(
                                'Chicks share (%)',
                                _chicksShare,
                                decimal: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _label('Product types available'),
                        Row(
                          children: [
                            Expanded(
                              child: VoiceTextField(
                                controller: _productTypeInput,
                                decoration:
                                    _decoration(hint: 'e.g. Feed, Chicks'),
                                onChanged: (_) {},
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              onPressed: _addProductType,
                              icon: const Icon(Icons.add_rounded),
                              style: IconButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        if (_productTypes.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _productTypes
                                .map(
                                  (t) => Chip(
                                    label: Text(
                                      t,
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                      ),
                                    ),
                                    onDeleted: () => setState(
                                      () => _productTypes.remove(t),
                                    ),
                                    deleteIconColor: AppColors.error,
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _numberField(
                                'Feed dealers',
                                _feedDealerCount,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _numberField(
                                'Chicks dealers',
                                _chicksDealerCount,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _label('Farms by bird type'),
                        Row(
                          children: [
                            Expanded(
                              child: _numberField('Broiler', _broilerFarms),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _numberField('Layer', _layerFarms),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _numberField('Color', _colorFarms),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _numberField('Cock', _cockFarms),
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
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            _sectionTitle('Competitor companies'),
                            TextButton.icon(
                              onPressed: _addCompetitorRow,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: Text(
                                'Add',
                                style: GoogleFonts.poppins(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        if (_competitors.isEmpty)
                          Text(
                            'No competitors added yet.',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: AppColors.textHint,
                            ),
                          ),
                        ..._competitors.asMap().entries.map(
                              (entry) => _competitorCard(
                                entry.key,
                                entry.value,
                              ),
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
                        VoiceTextField(
                          controller: _division,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('District'),
                        VoiceTextField(
                          controller: _district,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Upazila'),
                        VoiceTextField(
                          controller: _upazila,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Union'),
                        VoiceTextField(
                          controller: _union,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Village'),
                        VoiceTextField(
                          controller: _village,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Address'),
                        VoiceTextField(
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
                        VoiceTextField(
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
                                    _isEdit
                                        ? 'Update market'
                                        : 'Save market',
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

  Widget _competitorCard(int index, _CompetitorRow row) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: VoiceTextField(
                    controller: row.name,
                    decoration:
                        _decoration(hint: 'Competitor company name'),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 92,
                  child: VoiceTextField(
                    controller: row.sharePercent,
                    voiceEnabled: false,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _decoration(hint: 'Share %'),
                  ),
                ),
                IconButton(
                  onPressed: () => _removeCompetitorRow(index),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: AppColors.error,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            VoiceTextField(
              controller: row.note,
              decoration: _decoration(hint: 'Details (products, notes…)',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
