import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/marketing_demo_masters.dart';
import '../../models/booking_form_data_models.dart';
import '../../models/marketing_dealer.dart';
import '../../models/marketing_models.dart';
import '../../models/zone_scope.dart';
import '../../services/auth_service.dart';
import '../../services/marketing_master_service.dart';
import '../../services/marketing_service.dart';
import '../../services/sales_service.dart';
import '../../services/zone_scope_service.dart';
import '../../utils/marketing_location_helper.dart';
import '../../widgets/searchable_select_field.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/voice_input_field.dart';

class _ProductRow {
  final name = TextEditingController();
  final brand = TextEditingController();
  final demand = TextEditingController();
  final stock = TextEditingController();
  final unitPrice = TextEditingController();
  final competitor = TextEditingController();
  final notes = TextEditingController();
  String relationType = 'stock';
  MarketingDemoProduct? product;
  MarketingDemoNamed? category;
  MarketingDemoNamed? unit;
  BookingFormCompany? company;
  bool isOurProduct = true;

  void dispose() {
    name.dispose();
    brand.dispose();
    demand.dispose();
    stock.dispose();
    unitPrice.dispose();
    competitor.dispose();
    notes.dispose();
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
  final _ownerName = TextEditingController();
  final _code = TextEditingController();
  final _phone = TextEditingController();
  final _altPhone = TextEditingController();
  final _email = TextEditingController();
  final _nid = TextEditingController();
  final _tradeLicense = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  final _farmType = TextEditingController();
  final _capacity = TextEditingController();
  final _businessYears = TextEditingController();
  final _creditLimit = TextEditingController();

  String _partyType = 'dealer';
  String _paymentMode = 'cash';
  String _leadStatus = 'new';

  /// The employee's own zone, resolved from their HRM profile and shown
  /// read-only. It is a fact about who is filing the record, not a filter on
  /// the choices below.
  MarketingDemoNamed? _employeeZone;

  /// Company → sector → market, each chosen by the officer. The sector list
  /// narrows to the selected company and the market list to the selected
  /// sector; changing an upstream pick clears everything below it.
  BookingFormCompany? _selectedCompany;
  BookingFormSector? _selectedSector;
  Market? _selectedMarket;
  List<BookingFormCompany> _companies = const [];
  List<BookingFormSector> _sectors = const [];
  List<Market> _markets = const [];

  /// Server-allocated `DLR-09260001` / `FMR-09260001`. Null until the endpoint
  /// answers, and left null on failure rather than invented locally — a code
  /// guessed on the device can collide, which is the whole reason it is
  /// allocated server-side.
  String? _generatedCode;
  bool _loadingCode = true;

  /// Party already holding the typed phone, when the uniqueness check finds one.
  Party? _phoneClash;

  /// Pending debounced phone lookup, cancelled on every keystroke.
  Timer? _phoneDebounce;

  /// Long enough to skip the searches for intermediate numbers, short enough
  /// that the verdict is there before the officer looks up from the keyboard.
  static const _phoneCheckDelay = Duration(milliseconds: 700);

  List<Party> _dealers = const [];

  /// Only the product rows still offer a company picker, so this stays the demo
  /// catalog. The party's own company comes from the officer's selection.
  final List<BookingFormCompany> _productCompanies =
      MarketingDemoMasters.companies;
  Party? _parentParty;
  MarketingDemoNamed? _capacityUnit;

  /// Dealers from the Sales master, offered by the existing-dealer picker.
  ///
  /// Replaces a hardcoded demo catalog that had no phone, address or zone on it,
  /// so selecting from it could never autofill anything. Only fetched while the
  /// party type is an existing dealer — see `_loadExistingDealers`.
  List<MarketingDealer> _existingDealers = const [];
  bool _loadingExistingDealers = false;
  MarketingDealer? _selectedExistingDealer;
  double? _lat;
  double? _lng;
  bool _loadingDealers = false;
  bool _loadingMasters = true;
  bool _resolvingLocation = true;
  String? _locationStatus;
  bool _submitting = false;
  final List<_ProductRow> _products = [];
  final List<XFile> _photos = [];

  static const _relationTypes = [
    'business',
    'uses',
    'sells',
    'stock',
    'demand',
    'competitor',
  ];
  static const _paymentModes = ['cash', 'credit', 'mixed', 'other'];
  static const _leadStatuses = ['new', 'warm', 'hot', 'converted', 'lost'];

  bool get _isFarm => _partyType == 'farm' || _partyType == 'farmer';

  /// The two dealer-facing types the form offers. `dealer` is a new dealer and
  /// `outlet` an existing one — both are already in the backend's party_type
  /// enum, so no server change was needed to name them properly.
  static const _dealerPartyTypes = [
    (label: 'New dealer', value: 'dealer'),
    (label: 'Existing dealer', value: 'outlet'),
  ];

  /// Code prefix per record kind.
  String get _codePrefix => _isFarm ? 'FMR' : 'DLR';

  /// A party's phone number identifies it, so it is required for every party
  /// this form creates — farm included.
  ///
  /// Uniqueness is checked against the *farm* pool rather than globally, because
  /// the server scopes the same way: a farm and a dealer may share a number,
  /// two farms may not. Checking the wrong pool would warn about a clash the
  /// index would never reject.
  static const bool _phoneRequired = true;

  /// Whether the typed phone is being checked in the farm pool.
  bool get _phoneInFarmPool => _isFarm;

  @override
  void initState() {
    super.initState();
    _partyType = widget.initialPartyType;
    _products.add(_ProductRow());
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _loadFormMasters(),
      _autoFillLocation(),
      _loadCode(),
      _loadOrgMasters(),
      if (_isFarm) _loadDealers(),
    ]);
  }

  /// Reserves the record code from the server.
  ///
  /// A failure is not fatal: the code is optional server-side, and a missing one
  /// is far better than a duplicate. The field then reads as unavailable rather
  /// than showing an empty box the officer might assume they can type into.
  Future<void> _loadCode() async {
    final result = await _service.nextCode(_codePrefix);
    if (!mounted) return;
    setState(() {
      _loadingCode = false;
      _generatedCode = result.success ? result.data : null;
    });
  }

  /// Resolves the employee's zone from their HRM profile.
  ///
  /// The zone is shown read-only on the form; it no longer decides which
  /// company, sector or market the officer may pick.
  Future<void> _loadZone() async {
    final scope = await ZoneScopeService.instance.load();
    if (!mounted || scope == null) return;
    final option = await _zoneOptionFor(scope);
    if (!mounted) return;
    setState(() => _employeeZone = option);
  }

  /// The profile's zone expressed as a picker option, matched by name.
  ///
  /// The option carries the Sales zone id rather than anything this app owns,
  /// which is the id the record is filed under.
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
      _selectedCompany?.id,
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
      // Everything below the company is now invalid: a sector from the old
      // company would file the record under a pairing that cannot exist.
      _selectedSector = null;
      _selectedMarket = null;
    });

    final sectors = await MarketingMasterService.instance.sectorsForCompany(
      company?.id,
    );
    if (!mounted) return;
    setState(() => _sectors = sectors);
  }

  /// The market list narrows to the chosen sector.
  Future<void> _onSectorSelected(BookingFormSector? sector) async {
    setState(() {
      _selectedSector = sector;
      _selectedMarket = null;
    });

    final markets = await MarketingMasterService.instance.marketsForSector(
      sector?.id,
    );
    if (!mounted) return;
    setState(() => _markets = markets);
  }

  /// Loads the existing-dealer list.
  ///
  /// Only ever called while the party type is an existing dealer — the picker
  /// is not rendered otherwise, so fetching for a new dealer or a farm would be
  /// a request nobody can use.
  ///
  /// Unfiltered: the Sales dealer master carries no company or sector edge, so
  /// there is nothing to narrow it by, and narrowing by the employee's zone
  /// would hide dealers they legitimately trade with. The picker is searchable.
  ///
  /// A failure is not fatal: the picker then offers nothing and the officer can
  /// still register the dealer by hand. The Sales master sits behind a public
  /// endpoint that can 500 on unrelated data, so this has to be a soft failure.
  Future<void> _loadExistingDealers() async {
    setState(() => _loadingExistingDealers = true);
    final result = await _service.listExistingDealers(limit: 200);
    if (!mounted) return;
    setState(() {
      _loadingExistingDealers = false;
      _existingDealers = result.success
          ? (result.data ?? const <MarketingDealer>[])
          : const <MarketingDealer>[];
    });
  }

  /// Fills whatever the chosen ERP dealer actually carries.
  ///
  /// Each field is written only when the source has a value, so a dealer with no
  /// address does not blank an address the officer has already typed. The phone
  /// is the exception worth noting: it is required, and the debounce in
  /// [_onPhoneChanged] re-runs against the new value.
  void _applyExistingDealer(MarketingDealer? dealer) {
    if (dealer == null) return;

    void fillIfEmpty(TextEditingController controller, String? value) {
      final text = (value ?? '').trim();
      if (text.isEmpty) return;
      if (controller.text.trim().isNotEmpty) return;
      controller.text = text;
    }

    fillIfEmpty(_contact, dealer.contactPerson);
    fillIfEmpty(_phone, dealer.phone);
    fillIfEmpty(_altPhone, dealer.altPhone);
    fillIfEmpty(_address, dealer.address);

    // A selected dealer is a fact about the record, so it goes in the payload
    // even though the field is otherwise absent from the farm form.
    setState(() {
      _selectedExistingDealer = dealer;
      _phoneClash = null;
    });
  }

  @override
  void dispose() {
    _phoneDebounce?.cancel();
    _name.dispose();
    _tradeName.dispose();
    _contact.dispose();
    _ownerName.dispose();
    _code.dispose();
    _phone.dispose();
    _altPhone.dispose();
    _email.dispose();
    _nid.dispose();
    _tradeLicense.dispose();
    _address.dispose();
    _notes.dispose();
    _farmType.dispose();
    _capacity.dispose();
    _businessYears.dispose();
    _creditLimit.dispose();
    for (final p in _products) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _loadFormMasters() async {
    // The zone comes from the employee's profile and the org pickers from the
    // Sales master. This only has to wait long enough for the pickers to stop
    // showing a spinner while the first load is still in flight.
    await Future.wait([
      _loadZone(),
      _salesService.fetchBookingFormData(),
      ZoneScopeService.instance.loadZoneOptions(),
    ]);
    if (!mounted) return;
    setState(() => _loadingMasters = false);
  }

  Future<void> _loadDealers() async {
    setState(() => _loadingDealers = true);
    // Parent dealer picker is company-wide (omit employee_id).
    final result = await _service.listParties(partyType: 'dealer');
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

  /// Checks whether the typed phone already belongs to another party.
  ///
  /// The backend `q` filter is a substring LIKE, so every hit is compared after
  /// `normalisePhone` — otherwise `+8801712…` would not be recognised as the
  /// same number as `01712…` and the duplicate would slip through.
  Future<void> _checkPhone() async {
    final typed = _phone.text.trim();
    if (typed.isEmpty) {
      if (_phoneClash != null) setState(() => _phoneClash = null);
      return;
    }

    final result = await _service.findPartiesByPhone(typed);
    if (!mounted) return;

    if (!result.success) {
      // A failed lookup is not a pass. The server still enforces uniqueness on
      // submit, so this only means the early warning is unavailable.
      setState(() => _phoneClash = null);
      return;
    }

    Party? clash;
    for (final party in result.data ?? const <Party>[]) {
      if (MarketingService.samePhone(party.phone, typed)) {
        // Only a clash inside the same pool is one. The server scopes its
        // unique index the same way, so a farm sharing a number with a dealer is
        // legal and must not be flagged — warning about it would block a save
        // the database would happily accept.
        if (party.isFarm != _phoneInFarmPool) continue;
        clash = party;
        break;
      }
    }
    setState(() => _phoneClash = clash);
  }

  /// Debounces the uniqueness lookup while the number is being typed.
  ///
  /// Without the delay every keystroke would fire a search. [Timer] rather than
  /// a `Future.delayed` chain so a fast typist cancels the pending check
  /// instead of queueing one per character.
  void _onPhoneChanged() {
    _phoneClash = null;
    _phoneDebounce?.cancel();
    final typed = _phone.text.trim();
    if (typed.isEmpty) {
      setState(() {});
      return;
    }
    _phoneDebounce = Timer(_phoneCheckDelay, _checkPhone);
  }

  String? get _phoneError {
    if (_phoneClash != null) {
      final code = _phoneClash!.code;
      return 'Already linked to ${_phoneClash!.displayName}'
          '${code != null && code.isNotEmpty ? ' ($code)' : ''}';
    }
    if (_phoneRequired && _phone.text.trim().isEmpty) {
      return 'Phone is required.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      _snack('Name is required.');
      return;
    }
    if (_phoneRequired && _phone.text.trim().isEmpty) {
      _snack('Phone is required.');
      return;
    }
    // Re-check rather than trusting the blur-time result: the check runs on a
    // debounce and the officer may have edited the number since.
    await _checkPhone();
    if (!mounted) return;
    if (_phoneClash != null) {
      _snack(
        _isFarm
            ? 'That phone number is already linked to another farm.'
            : 'That phone number is already linked to another dealer.',
      );
      return;
    }
    // Every party is filed under the employee's zone, farm included — the zone
    // is what every marketing list and report filters on, so an untagged farm
    // is as unreachable as an untagged dealer.
    if (_employeeZone == null) {
      _snack(
        'Your zone could not be resolved. Ask an admin to set your zone, then retry.',
      );
      return;
    }
    // The officer files under a company, so one is required. Sector and market
    // stay optional: they narrow the record further, but a dealer registered
    // against the right company is still findable without them.
    if (_selectedCompany == null) {
      _snack(
        'Choose the company this ${_isFarm ? 'farm' : 'dealer'} belongs to.',
      );
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
      var name = row.name.text.trim();
      if (name.isEmpty && row.product != null) {
        name = row.product!.name;
      }
      if (name.isEmpty) continue;
      products.add({
        'product_name': name,
        'relation_type': row.relationType,
        if (row.product != null) 'product_id': row.product!.id,
        if (row.category != null) 'product_category_id': row.category!.id,
        if (row.category != null) 'category_name': row.category!.name,
        if (row.company != null) 'company_id': row.company!.id,
        if (row.unit != null) 'unit_id': row.unit!.id,
        if (row.unit != null) 'unit': row.unit!.name,
        if (row.brand.text.trim().isNotEmpty)
          'brand_name': row.brand.text.trim(),
        if (row.demand.text.trim().isNotEmpty)
          'monthly_quantity': double.tryParse(row.demand.text.trim()),
        if (row.demand.text.trim().isNotEmpty)
          'demand_qty': double.tryParse(row.demand.text.trim()),
        if (row.stock.text.trim().isNotEmpty)
          'current_stock': double.tryParse(row.stock.text.trim()),
        if (row.stock.text.trim().isNotEmpty)
          'stock_qty': double.tryParse(row.stock.text.trim()),
        if (row.unitPrice.text.trim().isNotEmpty)
          'unit_price': double.tryParse(row.unitPrice.text.trim()),
        if (row.competitor.text.trim().isNotEmpty)
          'competitor_company': row.competitor.text.trim(),
        'is_our_product': row.isOurProduct,
        if (row.notes.text.trim().isNotEmpty) 'notes': row.notes.text.trim(),
      });
    }

    final payload = <String, dynamic>{
      'employee_id': employeeId,
      'party_type': _partyType,
      'name': _name.text.trim(),
      if (_tradeName.text.trim().isNotEmpty)
        'trade_name': _tradeName.text.trim(),
      // The server-allocated code wins over anything typed: the field is
      // read-only, and _code is only ever seeded for backwards compatibility.
      if (_generatedCode != null && _generatedCode!.isNotEmpty)
        'code': _generatedCode
      else if (_code.text.trim().isNotEmpty)
        'code': _code.text.trim(),
      if (_contact.text.trim().isNotEmpty)
        'contact_person': _contact.text.trim(),
      if (_ownerName.text.trim().isNotEmpty)
        'owner_name': _ownerName.text.trim(),
      if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
      if (_altPhone.text.trim().isNotEmpty) 'alt_phone': _altPhone.text.trim(),
      if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
      if (_nid.text.trim().isNotEmpty) 'nid_no': _nid.text.trim(),
      if (_tradeLicense.text.trim().isNotEmpty)
        'trade_license_no': _tradeLicense.text.trim(),
      if (_address.text.trim().isNotEmpty) 'address': _address.text.trim(),
      // The zone is the employee's own and is filed as-is. Company, sector and
      // market are the officer's picks, sent with both the id and the name so
      // the webapp reports can read them without a master to join against.
      if (_selectedMarket != null) 'market_id': _selectedMarket!.id,
      if (_isFarm && _parentParty != null) 'parent_party_id': _parentParty!.id,
      if (_selectedExistingDealer != null)
        'existing_dealer_id': _selectedExistingDealer!.sourceId,
      if (_selectedCompany != null) 'company_id': _selectedCompany!.id,
      if (_selectedCompany != null)
        'company_name': _selectedCompany!.displayName,
      if (_selectedSector != null) 'sector_id': _selectedSector!.id,
      if (_selectedSector != null) 'sector_name': _selectedSector!.name,
      if (_employeeZone != null) 'zone_id': _employeeZone!.id,
      if (_employeeZone != null) 'zone_name': _employeeZone!.name,
      if (_isFarm && _farmType.text.trim().isNotEmpty)
        'farm_type': _farmType.text.trim(),
      if (_isFarm && _capacity.text.trim().isNotEmpty)
        'capacity': double.tryParse(_capacity.text.trim()),
      if (_capacityUnit != null) 'capacity_unit_id': _capacityUnit!.id,
      if (_businessYears.text.trim().isNotEmpty)
        'business_years': double.tryParse(_businessYears.text.trim()),
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
      fillColor: AppColors.surfaceSunk,
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
        style: AppType.meta.copyWith(
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
        style: AppType.body.copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _isFarm ? 'New Farm' : 'New Dealer';
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Column(
        children: [
          AppHeader(
            title: title,
            subtitle: 'Identity, contact, credit & products',
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.gutter,
                AppSpace.md,
                AppSpace.gutter,
                AppSpace.xl,
              ),
              child: Column(
                children: [
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionTitle('Basic'),
                        // A farm is reached from the Farms tab, so the screen is
                        // already farm-specific and the type is a fact rather
                        // than a choice. Dealers get the two business-meaningful
                        // options; the other party_type values still exist in the
                        // data model and in existing records, they are just not
                        // something a field officer creates here.
                        if (_isFarm)
                          const ReadOnlyField(
                            label: 'Party type',
                            icon: Icons.category_outlined,
                            value: 'Farm',
                          )
                        else ...[
                          _label('Party type'),
                          DropdownButtonFormField<String>(
                            initialValue: _partyType,
                            decoration: _decoration(),
                            items: _dealerPartyTypes
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t.value,
                                    child: Text(t.label),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() {
                                _partyType = v;
                                _phoneClash = null;
                                // The picker belongs to the existing-dealer type
                                // alone, so its selection is cleared when the
                                // type moves away from it.
                                if (v != 'outlet') {
                                  _selectedExistingDealer = null;
                                }
                              });
                              if (v == 'outlet' && _existingDealers.isEmpty) {
                                _loadExistingDealers();
                              }
                            },
                          ),
                        ],
                        const SizedBox(height: 14),
                        _label('Name *'),
                        VoiceTextField(
                          controller: _name,
                          decoration: _decoration(hint: 'Party name'),
                        ),
                        const SizedBox(height: 14),
                        _label('Trade name'),
                        VoiceTextField(
                          controller: _tradeName,
                          decoration: _decoration(hint: 'Optional'),
                        ),
                        const SizedBox(height: 14),
                        // Allocated server-side so two officers opening this form
                        // at the same moment cannot be handed the same code.
                        ReadOnlyField(
                          label: 'Code',
                          icon: Icons.qr_code_2_outlined,
                          value: _generatedCode,
                          hint: _loadingCode
                              ? 'Generating…'
                              : 'Unavailable — will save without one',
                        ),
                        const SizedBox(height: 14),
                        // The existing ERP dealer picker appears only for the
                        // existing-dealer type. A new dealer or a farm has no
                        // ERP dealer to attach, so showing an always-visible
                        // field there just invited an officer to file a farm
                        // against a demo row.
                        if (_partyType == 'outlet') ...[
                          if (_loadingExistingDealers)
                            const LinearProgressIndicator()
                          else
                            SearchableSelectField<MarketingDealer>(
                              label: 'Existing ERP dealer',
                              icon: Icons.storefront_outlined,
                              options: _existingDealers,
                              selected: _selectedExistingDealer,
                              displayString: (d) => d.displayName,
                              searchText: (d) => d.searchText,
                              subtitleFor: (d) =>
                                  d.subtitle.isEmpty ? null : d.subtitle,
                              onSelected: _applyExistingDealer,
                            ),
                          const SizedBox(height: 14),
                        ],
                        // The zone is the officer's own territory and stays
                        // read-only. Company, sector and market are theirs to
                        // pick, cascading downwards: the zone deliberately does
                        // not narrow any of them, because an officer who trades
                        // across a neighbouring zone still has to be able to
                        // record it.
                        if (_loadingMasters)
                          const LinearProgressIndicator()
                        else ...[
                          ReadOnlyField(
                            label: 'Zone *',
                            icon: Icons.map_outlined,
                            value: _employeeZone?.name,
                            hint: 'Not set — ask an admin to set your zone',
                          ),
                          const SizedBox(height: 14),
                          SearchableSelectField<BookingFormCompany>(
                            label: 'Company *',
                            icon: Icons.apartment_outlined,
                            options: _companies,
                            selected: _selectedCompany,
                            displayString: (c) => c.displayName,
                            searchText: (c) => c.displayName.toLowerCase(),
                            onSelected: _onCompanySelected,
                          ),
                          const SizedBox(height: 14),
                          SearchableSelectField<BookingFormSector>(
                            label: 'Sector',
                            icon: Icons.hub_outlined,
                            options: _sectors,
                            selected: _selectedSector,
                            enabled: _selectedCompany != null,
                            hintText: _selectedCompany == null
                                ? 'Pick a company first'
                                : 'Tap to pick or type…',
                            displayString: (s) => s.name,
                            searchText: (s) => s.searchText,
                            onSelected: _onSectorSelected,
                          ),
                          const SizedBox(height: 14),
                          SearchableSelectField<Market>(
                            label: 'Market',
                            icon: Icons.store_mall_directory_outlined,
                            options: _markets,
                            selected: _selectedMarket,
                            enabled: _selectedSector != null,
                            hintText: _selectedSector == null
                                ? 'Pick a sector first'
                                : 'Tap to pick or type…',
                            displayString: (m) => m.displayName,
                            searchText: (m) =>
                                '${m.name} ${m.locationLine}'.toLowerCase(),
                            subtitleFor: (m) =>
                                m.locationLine.isEmpty ? null : m.locationLine,
                            onSelected: (m) =>
                                setState(() => _selectedMarket = m),
                          ),
                          const SizedBox(height: 14),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionTitle('Contact'),
                        _label('Contact person'),
                        VoiceTextField(
                          controller: _contact,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 14),
                        _label('Owner name'),
                        VoiceTextField(
                          controller: _ownerName,
                          decoration: _decoration(hint: 'Owner / proprietor'),
                        ),
                        const SizedBox(height: 14),
                        // A dealer is looked up by phone, so the number is
                        // required and has to belong to exactly one dealer.
                        // Re-checked on submit too, because the server is the
                        // real authority and the debounce can lag an edit.
                        _label('Phone *'),
                        VoiceTextField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          onChanged: (_) => _onPhoneChanged(),
                          decoration: _decoration().copyWith(
                            errorText: _phoneError,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _label('Alt phone'),
                        VoiceTextField(
                          controller: _altPhone,
                          keyboardType: TextInputType.phone,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 14),
                        _label('Email'),
                        VoiceTextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 14),
                        _label('NID'),
                        VoiceTextField(
                          controller: _nid,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 14),
                        _label('Trade license'),
                        VoiceTextField(
                          controller: _tradeLicense,
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
                        _sectionTitle('Farm & Credit'),
                        if (_isFarm) ...[
                          _label('Parent dealer'),
                          if (_loadingDealers)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else
                            SearchableSelectField<Party>(
                              label: 'Parent dealer',
                              icon: Icons.account_tree_outlined,
                              options: _dealers,
                              selected: _parentParty,
                              displayString: (d) => d.displayName,
                              searchText: (d) => d.displayName.toLowerCase(),
                              onSelected: (d) =>
                                  setState(() => _parentParty = d),
                            ),
                          const SizedBox(height: 14),
                          _label('Farm type'),
                          VoiceTextField(
                            controller: _farmType,
                            decoration: _decoration(
                              hint: 'e.g. Broiler, Layer',
                            ),
                          ),
                          const SizedBox(height: 14),
                          _label('Capacity'),
                          VoiceTextField(
                            controller: _capacity,
                            keyboardType: TextInputType.number,
                            decoration: _decoration(),
                          ),
                          const SizedBox(height: 14),
                          SearchableSelectField<MarketingDemoNamed>(
                            label: 'Capacity unit',
                            icon: Icons.straighten,
                            options: MarketingDemoMasters.units,
                            selected: _capacityUnit,
                            displayString: (u) => u.displayName,
                            searchText: (u) => u.searchText,
                            onSelected: (u) =>
                                setState(() => _capacityUnit = u),
                          ),
                          const SizedBox(height: 14),
                        ],
                        _label('Business years'),
                        VoiceTextField(
                          controller: _businessYears,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 14),
                        _label('Credit limit'),
                        VoiceTextField(
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
                                (p) =>
                                    DropdownMenuItem(value: p, child: Text(p)),
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
                                (p) =>
                                    DropdownMenuItem(value: p, child: Text(p)),
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
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionTitle('Location'),
                        _label('Address'),
                        VoiceTextField(
                          controller: _address,
                          maxLines: 2,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 14),
                        // The market picker moved up into the read-only scope
                        // block: it is now derived from the employee's zone and
                        // position rather than chosen here.
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
                          const SizedBox(height: 14),
                        ],
                        _label('Notes'),
                        VoiceTextField(
                          controller: _notes,
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
                                color: AppColors.surfaceSunk,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  SearchableSelectField<MarketingDemoProduct>(
                                    label: 'Product',
                                    icon: Icons.inventory_2_outlined,
                                    options: MarketingDemoMasters.products,
                                    selected: row.product,
                                    displayString: (p) => p.displayName,
                                    searchText: (p) => p.searchText,
                                    subtitleFor: (p) => p.categoryName,
                                    onSelected: (p) {
                                      setState(() {
                                        row.product = p;
                                        if (p != null) {
                                          row.name.text = p.name;
                                          row.isOurProduct = p.ourProduct;
                                          row.category =
                                              MarketingDemoMasters.byId(
                                                MarketingDemoMasters.categories,
                                                p.categoryId,
                                                (c) => c.id,
                                              );
                                          row.company =
                                              MarketingDemoMasters.byId(
                                                _productCompanies,
                                                p.companyId,
                                                (c) => c.id,
                                              );
                                        }
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  VoiceTextField(
                                    controller: row.name,
                                    decoration: _decoration(
                                      hint: 'Product name (required)',
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    initialValue: row.relationType,
                                    decoration: _decoration(
                                      hint: 'Relation type',
                                    ),
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
                                  SearchableSelectField<MarketingDemoNamed>(
                                    label: 'Category',
                                    icon: Icons.category_outlined,
                                    options: MarketingDemoMasters.categories,
                                    selected: row.category,
                                    displayString: (c) => c.displayName,
                                    searchText: (c) => c.searchText,
                                    onSelected: (c) =>
                                        setState(() => row.category = c),
                                  ),
                                  const SizedBox(height: 8),
                                  SearchableSelectField<MarketingDemoNamed>(
                                    label: 'Unit',
                                    icon: Icons.straighten,
                                    options: MarketingDemoMasters.units,
                                    selected: row.unit,
                                    displayString: (u) => u.displayName,
                                    searchText: (u) => u.searchText,
                                    onSelected: (u) =>
                                        setState(() => row.unit = u),
                                  ),
                                  const SizedBox(height: 8),
                                  SearchableSelectField<BookingFormCompany>(
                                    label: 'Product company',
                                    icon: Icons.apartment_outlined,
                                    options: _productCompanies,
                                    selected: row.company,
                                    displayString: (c) => c.displayName,
                                    searchText: (c) =>
                                        c.displayName.toLowerCase(),
                                    onSelected: (c) =>
                                        setState(() => row.company = c),
                                  ),
                                  const SizedBox(height: 8),
                                  VoiceTextField(
                                    controller: row.brand,
                                    decoration: _decoration(hint: 'Brand name'),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: VoiceTextField(
                                          controller: row.demand,
                                          keyboardType: TextInputType.number,
                                          decoration: _decoration(
                                            hint: 'Monthly / demand',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: VoiceTextField(
                                          controller: row.stock,
                                          keyboardType: TextInputType.number,
                                          decoration: _decoration(
                                            hint: 'Stock',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  VoiceTextField(
                                    controller: row.unitPrice,
                                    keyboardType: TextInputType.number,
                                    decoration: _decoration(hint: 'Unit price'),
                                  ),
                                  const SizedBox(height: 8),
                                  VoiceTextField(
                                    controller: row.competitor,
                                    decoration: _decoration(
                                      hint: 'Competitor company',
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      'Our product',
                                      style: AppType.bodySm,
                                    ),
                                    value: row.isOurProduct,
                                    onChanged: (v) =>
                                        setState(() => row.isOurProduct = v),
                                  ),
                                  VoiceTextField(
                                    controller: row.notes,
                                    decoration: _decoration(
                                      hint: 'Product notes',
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
                  AppCard(
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
}
