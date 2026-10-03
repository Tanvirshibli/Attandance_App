import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/marketing_demo_masters.dart';
import '../../models/booking_form_data_models.dart';
import '../../models/marketing_models.dart';
import '../../models/zone_scope.dart';
import '../../services/auth_service.dart';
import '../../services/marketing_master_service.dart';
import '../../services/marketing_service.dart';
import '../../services/permission_service.dart';
import '../../services/zone_scope_service.dart';
import '../../utils/marketing_location_helper.dart';
import '../../widgets/searchable_select_field.dart';
import '../../widgets/ui/ui.dart';
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
  final AuthService _authService = AuthService();

  final _name = TextEditingController();
  final _phone = TextEditingController();
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

  /// The employee's zone, shown read-only. On edit the market's own stored zone
  /// wins — a saved record is never re-scoped to whoever opens it.
  MarketingDemoNamed? _employeeZone;

  /// Company and sector are the officer's own picks, with the sector list
  /// narrowing to the chosen company. A market belongs to exactly one of each,
  /// so both are required here.
  BookingFormCompany? _selectedCompany;
  BookingFormSector? _selectedSector;
  List<BookingFormCompany> _companies = const [];
  List<BookingFormSector> _sectors = const [];

  /// Server-allocated `MRK-09260001`. Null on failure rather than invented on
  /// the device.
  String? _generatedCode;
  bool _loadingCode = true;

  /// Market already holding the typed phone, when the check finds one.
  Market? _phoneClash;
  Timer? _phoneDebounce;

  static const _phoneCheckDelay = Duration(milliseconds: 700);

  final List<XFile> _photos = [];
  String _status = 'active';
  double? _lat;
  double? _lng;
  bool _resolvingLocation = true;
  String? _locationStatus;
  bool _submitting = false;
  int? _employeeId;

  bool get _isEdit => widget.market != null;

  /// Whether the sector picker belongs on this form right now.
  ///
  /// A market sits under one company and one sector, so sector is required —
  /// except when the chosen company has no sectors in the Sales org master at
  /// all. That happens for the curated Bangladesh companies (Kazi Farms, CP
  /// Bangladesh, ACI Godrej and the rest), which are not part of that master.
  /// The picker is hidden in that case and the sector key is omitted from the
  /// payload, rather than showing a required field with nothing in it.
  bool get _showSector => _selectedCompany?.hasSectors ?? true;

  /// The code to submit.
  ///
  /// A saved market keeps the code it already has — renumbering it would break
  /// every reference to it. Only a new market takes the freshly allocated one,
  /// and a market with neither simply sends no code, which the API allows.
  String? get _effectiveCode {
    if (_isEdit) return widget.market!.code ?? _generatedCode;
    return _generatedCode;
  }

  @override
  void initState() {
    super.initState();
    _prefillFromMarket();
    _loadEmployee();
    _autoFillLocation();
    _loadCode();
    _loadOrgMasters();
    _loadZone();
  }

  void _prefillFromMarket() {
    final m = widget.market;
    if (m == null) return;
    _name.text = m.name;
    _phone.text = m.phone ?? '';
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
  }

  @override
  void dispose() {
    _phoneDebounce?.cancel();
    _name.dispose();
    _phone.dispose();
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

  /// Reserves the record code from the server. A failure is not fatal: the code
  /// is optional server-side and an absent one beats a duplicate.
  Future<void> _loadCode() async {
    final result = await _service.nextCode('MRK');
    if (!mounted) return;
    setState(() {
      _loadingCode = false;
      _generatedCode = result.success ? result.data : null;
    });
  }

  /// Resolves the employee's zone from their HRM profile.
  ///
  /// The zone is shown read-only; it no longer decides which company or sector
  /// the officer may pick.
  Future<void> _loadZone() async {
    final scope = await ZoneScopeService.instance.load();
    if (!mounted || scope == null) return;
    final option = await _zoneOptionFor(scope);
    if (!mounted) return;
    setState(() => _employeeZone = option);
  }

  /// The profile's zone expressed as a picker option, matched by name. The
  /// option carries the Sales zone id, which is the id the record is filed under.
  static Future<MarketingDemoNamed?> _zoneOptionFor(ZoneScope scope) async {
    final options = await ZoneScopeService.instance.loadZoneOptions();

    for (final option in options) {
      if (scope.zoneNames.contains(option.name.toLowerCase())) return option;
    }
    return null;
  }

  /// Loads the company list and, until one is chosen, the full sector list.
  Future<void> _loadOrgMasters() async {
    final companies = await MarketingMasterService.instance.companies();
    final sectors = await MarketingMasterService.instance.sectorsForCompany(
      null,
    );
    if (!mounted) return;
    setState(() {
      _companies = companies;
      _sectors = sectors;
    });
  }

  /// The sector list narrows to the chosen company.
  Future<void> _onCompanySelected(BookingFormCompany? company) async {
    setState(() {
      _selectedCompany = company;
      // A sector from the previous company would file the market under a
      // pairing that cannot exist.
      _selectedSector = null;
    });

    final sectors = await MarketingMasterService.instance.sectorsForCompany(
      company?.id,
    );
    if (!mounted) return;
    setState(() => _sectors = sectors);
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
          _locationStatus = 'Location unavailable — fill geo fields manually.';
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

  /// Checks whether the typed phone already belongs to another market.
  ///
  /// The backend `q` filter is a substring LIKE, so hits are compared after
  /// `normalisePhone` before being treated as the same number.
  Future<void> _checkPhone() async {
    final typed = _phone.text.trim();
    if (typed.isEmpty) {
      if (_phoneClash != null) setState(() => _phoneClash = null);
      return;
    }

    final result = await _service.findMarketsByPhone(typed);
    if (!mounted) return;

    if (!result.success) {
      // Not a pass — just no early warning. The server still enforces it.
      setState(() => _phoneClash = null);
      return;
    }

    Market? clash;
    for (final market in result.data ?? const <Market>[]) {
      if (MarketingService.samePhone(market.phone, typed)) {
        clash = market;
        break;
      }
    }
    setState(() => _phoneClash = clash);
  }

  void _onPhoneChanged() {
    _phoneClash = null;
    _phoneDebounce?.cancel();
    if (_phone.text.trim().isEmpty) {
      setState(() {});
      return;
    }
    _phoneDebounce = Timer(_phoneCheckDelay, _checkPhone);
  }

  String? get _phoneError {
    if (_phoneClash != null) {
      return 'Already linked to ${_phoneClash!.name}';
    }
    if (_phone.text.trim().isEmpty) {
      return 'Phone is required.';
    }
    return null;
  }

  Future<void> _pickPhotos() async {
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return;
    setState(() => _photos.addAll(files));
  }

  Map<String, dynamic> _payload() {
    final competitors = _competitors
        .where((r) => r.name.text.trim().isNotEmpty)
        .map(
          (r) => {
            'name': r.name.text.trim(),
            if (double.tryParse(r.sharePercent.text.trim()) != null)
              'share_percent': double.tryParse(r.sharePercent.text.trim()),
            if (r.note.text.trim().isNotEmpty) 'note': r.note.text.trim(),
          },
        )
        .toList();

    return {
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
      if (_effectiveCode != null) 'code': _effectiveCode,
      // Scoped ids are written only when one actually resolved; a guessed id
      // would mis-file the market for every zone-scoped list.
      if (_selectedCompany != null) 'company_id': _selectedCompany!.id,
      if (_selectedCompany != null)
        'company_name': _selectedCompany!.displayName,
      if (_selectedSector != null) 'sector_id': _selectedSector!.id,
      if (_selectedSector != null) 'sector_name': _selectedSector!.name,
      if (_employeeZone != null) 'zone_id': _employeeZone!.id,
      if (_employeeZone != null) 'zone_name': _employeeZone!.name,
      if (_division.text.trim().isNotEmpty)
        'division_name': _division.text.trim(),
      if (_district.text.trim().isNotEmpty) 'district': _district.text.trim(),
      if (_upazila.text.trim().isNotEmpty) 'upazila': _upazila.text.trim(),
      if (_union.text.trim().isNotEmpty) 'union_name': _union.text.trim(),
      if (_village.text.trim().isNotEmpty) 'village_name': _village.text.trim(),
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
      if (_employeeId != null && _employeeId! > 0) 'employee_id': _employeeId,
    };
  }

  Future<void> _submit() async {
    // Defence in depth: the create pill on the hub is already gated, so a user
    // without `markets.create` cannot reach this form by tapping. Re-checked
    // here because a stale navigation stack or a future deep link could land on
    // it. An edit is left alone — correcting an existing record is not the
    // same act as filing a new one.
    if (!_isEdit && !PermissionService.instance.canCreateIn('market')) {
      _snack(PermissionService.instance.denialMessage('market'));
      return;
    }
    if (_name.text.trim().isEmpty) {
      _snack('Market name is required.');
      return;
    }
    if (_phone.text.trim().isEmpty) {
      _snack('Phone is required.');
      return;
    }
    // Re-check rather than trusting the debounced result: the server is the
    // authority and the debounce can lag an edit.
    await _checkPhone();
    if (!mounted) return;
    if (_phoneClash != null) {
      _snack('That phone number is already linked to another market.');
      return;
    }
    // A market belongs to a zone, and every zone-scoped list and report keys
    // off it — so an untagged market is invisible to the officer who filed it.
    // An edit keeps the zone the saved market already carries, so correcting a
    // survey is never blocked by a scope that has since changed.
    final effectiveZoneName = _isEdit
        ? widget.market!.zoneName
        : _employeeZone?.name;
    if (effectiveZoneName == null || effectiveZoneName.trim().isEmpty) {
      _snack(
        'Your zone could not be resolved. Ask an admin to set your zone, then retry.',
      );
      return;
    }
    // A market sits under exactly one company and one sector, so both are
    // required here — unlike a dealer, where the sector only narrows further.
    if (_selectedCompany == null) {
      _snack('Choose the company this market belongs to.');
      return;
    }
    // Only enforced when the picker is actually on screen. A company with no
    // sectors in the master has no sector to choose, and blocking there would
    // be a dead end with nothing the officer could do about it.
    if (_showSector && _selectedSector == null) {
      _snack('Choose the sector this market belongs to.');
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
      _snack(
        result.message ?? 'Could not ${_isEdit ? 'update' : 'create'} market.',
      );
      return;
    }

    final market = result.data!;
    if (_photos.isNotEmpty && _employeeId != null) {
      final upload = await _service.uploadAttachments(
        attachableType: 'market',
        attachableId: market.id,
        employeeId: _employeeId!,
        photos: _photos.map((x) => File(x.path)).toList(),
      );
      if (!upload.success) {
        // The market row exists; the photos can be re-uploaded from the record
        // rather than losing the whole submission.
        _snack('Market saved, but photos failed to upload: ${upload.message}');
      }
    }

    if (!mounted) return;
    _snack(_isEdit ? 'Market updated.' : 'Market saved.');
    Navigator.of(context).pop(market);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  InputDecoration _decoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: AppColors.surfaceSunk,
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
        style: AppType.bodySm.copyWith(
          fontWeight: FontWeight.w500,
          color: AppColors.inkMuted,
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: AppType.h3.copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
    );
  }

  Widget _numberField(
    String label,
    TextEditingController c, {
    String? hint,
    bool decimal = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(label),
        VoiceTextField(
          controller: c,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          decoration: _decoration(hint: hint),
        ),
      ],
    );
  }

  void _addProductType() {
    final value = _productTypeInput.text.trim();
    if (value.isEmpty) return;
    setState(() {
      if (!_productTypes.any((t) => t.toLowerCase() == value.toLowerCase())) {
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
      backgroundColor: AppColors.canvas,
      body: Column(
        children: [
          AppHeader(
            title: _isEdit ? 'Market survey — edit' : 'New Market',
            subtitle: _isEdit
                ? 'Update market intel & location'
                : 'Location & geo hierarchy',
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.md,
                AppSpace.md,
                AppSpace.md,
                AppSpace.xl,
              ),
              child: Column(
                children: [
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionTitle('Identity'),
                        _label('Name *'),
                        VoiceTextField(
                          controller: _name,
                          decoration: _decoration(hint: 'Market name'),
                        ),
                        const SizedBox(height: 12),
                        // A market is reachable by phone from the field, and one
                        // number belongs to one market.
                        _label('Phone *'),
                        VoiceTextField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          voiceEnabled: false,
                          onChanged: (_) => _onPhoneChanged(),
                          decoration: _decoration().copyWith(
                            errorText: _phoneError,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Allocated server-side so two officers opening this
                        // form at the same moment cannot be handed one code.
                        ReadOnlyField(
                          label: 'Code',
                          icon: Icons.qr_code_2_outlined,
                          value: _effectiveCode,
                          hint: _loadingCode
                              ? 'Generating…'
                              : 'Unavailable — will save without one',
                        ),
                        const SizedBox(height: 12),
                        // The zone is the officer's own territory and stays
                        // read-only. Company and sector are theirs to pick, the
                        // sector narrowing to the company — a market belongs to
                        // exactly one of each, so both are required.
                        ReadOnlyField(
                          label: 'Zone',
                          icon: Icons.map_outlined,
                          value: _isEdit
                              ? (widget.market!.zoneName ?? 'Not set')
                              : _employeeZone?.name,
                          hint: 'Not set — ask an admin to set your zone',
                        ),
                        const SizedBox(height: 12),
                        SearchableSelectField<BookingFormCompany>(
                          label: 'Company *',
                          icon: Icons.apartment_outlined,
                          options: _companies,
                          selected: _selectedCompany,
                          displayString: (c) => c.displayName,
                          searchText: (c) => c.displayName.toLowerCase(),
                          onSelected: _onCompanySelected,
                        ),
                        const SizedBox(height: 12),
                        // Hidden rather than disabled when the chosen company has
                        // no sectors. Sectors are still read live from the Sales
                        // org master, and the curated Bangladesh company master
                        // is not part of it — so a company like Kazi Farms has no
                        // `companyId` on any sector row and this picker would
                        // offer nothing. Sector is required on a market, so
                        // leaving an empty required field on screen would
                        // dead-end the form at submit with no way to explain why.
                        if (_showSector) ...[
                          SearchableSelectField<BookingFormSector>(
                            label: 'Sector *',
                            icon: Icons.hub_outlined,
                            options: _sectors,
                            selected: _selectedSector,
                            enabled: _selectedCompany != null,
                            hintText: _selectedCompany == null
                                ? 'Pick a company first'
                                : 'Tap to pick or type…',
                            displayString: (s) => s.name,
                            searchText: (s) => s.searchText,
                            onSelected: (s) =>
                                setState(() => _selectedSector = s),
                          ),
                          const SizedBox(height: 12),
                        ],
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
                  AppCard(
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
                                decoration: _decoration(
                                  hint: 'e.g. Feed, Chicks',
                                ),
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
                                    label: Text(t, style: AppType.meta),
                                    onDeleted: () =>
                                        setState(() => _productTypes.remove(t)),
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
                            Expanded(child: _numberField('Layer', _layerFarms)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _numberField('Color', _colorFarms)),
                            const SizedBox(width: 8),
                            Expanded(child: _numberField('Cock', _cockFarms)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _sectionTitle('Competitor companies'),
                            TextButton.icon(
                              onPressed: _addCompetitorRow,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: Text('Add', style: AppType.bodySm),
                            ),
                          ],
                        ),
                        if (_competitors.isEmpty)
                          Text(
                            'No competitors added yet.',
                            style: AppType.meta.copyWith(
                              color: AppColors.inkFaint,
                            ),
                          ),
                        ..._competitors.asMap().entries.map(
                          (entry) => _competitorCard(entry.key, entry.value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionTitle('Location'),
                        if (_locationStatus != null) ...[
                          Text(
                            _locationStatus!,
                            style: AppType.meta.copyWith(
                              color: _resolvingLocation
                                  ? AppColors.inkFaint
                                  : AppColors.inkMuted,
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
                  AppCard(
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
                                    _isEdit ? 'Update market' : 'Save market',
                                    style: AppType.body.copyWith(
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
          color: AppColors.surfaceSunk,
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
                    decoration: _decoration(hint: 'Competitor company name'),
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
              decoration: _decoration(hint: 'Details (products, notes…)'),
            ),
          ],
        ),
      ),
    );
  }
}
