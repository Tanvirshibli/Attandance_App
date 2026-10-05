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
import 'farm_survey_form_screen.dart';

/// One product line on the farm form.
///
/// Deliberately a private type in this file rather than the shared `_ProductRow`
/// in `party_form_screen.dart`: the two rows no longer collect the same fields,
/// and sharing one would mean every add/remove here reaches into the dealer
/// form's layout.
class _FarmProductRow {
  final name = TextEditingController();
  final brand = TextEditingController();
  final demand = TextEditingController();
  final notes = TextEditingController();
  String relationType = 'business';
  MarketingDemoProduct? product;
  MarketingDemoNamed? category;
  MarketingDemoNamed? unit;
  BookingFormCompany? company;
  bool isOurProduct = true;

  void dispose() {
    name.dispose();
    brand.dispose();
    demand.dispose();
    notes.dispose();
  }
}

/// Add Farm — a screen of its own, not a mode of the dealer form.
///
/// `PartyFormScreen` used to render both, split by a `_isFarm` boolean, which
/// meant every layout change here would have rippled through Add dealer and Add
/// market. Farm collection has its own field set and its own order now, so it
/// gets its own file. The dealer form is untouched.
///
/// The screen opens on a **duplicate check** rather than a blank form. A farm is
/// identified by its phone and found by its name, so the officer searches first;
/// a hit offers to post a visit report against the farm that already exists
/// instead of filing the same farm twice.
class FarmFormScreen extends StatefulWidget {
  const FarmFormScreen({super.key});

  @override
  State<FarmFormScreen> createState() => _FarmFormScreenState();

  /// How the officer classifies this farm. Not the same thing as
  /// `mkt_visits.visit_type`, which records what a *visit* was — this is a
  /// property of the farm itself, which is why it lives on `mkt_parties`.
  ///
  /// The values are what the API stores; the labels are what the officer reads.
  /// The backend enforces the same set with
  /// `in:regular_farm,model_farm,other_farm`.
  static const visitTypes = [
    (value: 'regular_farm', label: 'Regular farm'),
    (value: 'model_farm', label: 'Model farm'),
    (value: 'other_farm', label: 'Other farm'),
  ];

  static const farmTypes = [
    (value: 'broiler', label: 'Broiler'),
    (value: 'layer', label: 'Layer'),
    (value: 'color', label: 'Color'),
    (value: 'all', label: 'All'),
  ];

  /// The visit type a new farm gets before the officer picks another.
  static const defaultVisitType = 'regular_farm';

  /// The farm type a new farm gets before the officer picks another.
  static const defaultFarmType = 'broiler';

  /// Seven digits is the shortest run that cannot be an ordinary word, so a
  /// numeric string of at least this length is read as a phone.
  static const minPhoneDigits = 7;

  /// The company a new farm is filed under by default.
  ///
  /// Matched on a lowercased substring rather than an exact string, because the
  /// Sales master spells it several ways across modules — "Peoples Poultry &
  /// Hatchery Ltd" and "Peoples Poultry and Hatchery Ltd" are the same
  /// company, and `&` vs `and` is not a distinction worth a 422.
  ///
  /// Falls back to the first company when nothing matches: an officer who has
  /// to go hunting through a picker for the only company this app trades under
  /// is an officer who will eventually file the farm under the wrong one. A
  /// genuinely empty list returns null, and submit already blocks on that.
  static BookingFormCompany? defaultCompany(
    List<BookingFormCompany> companies,
  ) {
    if (companies.isEmpty) return null;
    for (final company in companies) {
      final name = company.displayName.toLowerCase();
      // The apostrophe is not consistent across the masters this can draw on:
      // Sales spells it "Peoples Poultry and Hatchery Ltd", the curated
      // Bangladesh master spells it "People's Poultry & Hatchery Ltd" (SL 19),
      // and older demo rows have used both. Matching on "peoples poultry" alone
      // would silently miss the apostrophe spelling and fall through to the
      // first company in the list, which files the farm under the wrong
      // company.
      if (name.contains('peoples poultry') ||
          name.contains("people's poultry")) {
        return company;
      }
    }
    return companies.first;
  }

  /// Whether [text] reads as a phone number rather than a farm name.
  ///
  /// Drives which field the search query seeds when the officer commits to
  /// adding a new farm.
  static bool looksLikePhone(String text) =>
      MarketingService.normalisePhone(text).length >= minPhoneDigits;

  /// The farm the query names exactly, if any.
  ///
  /// A phone query can only be answered by comparing digits — the backend `q`
  /// is a substring `LIKE`, so `01712345678` also matches `017123456789`. A name
  /// query takes the closest spelling, which is the first hit.
  ///
  /// Static and pure so the rule is testable without a network round-trip.
  static Party? exactFarmMatch(List<Party> farms, String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty || farms.isEmpty) return null;

    if (looksLikePhone(trimmed)) {
      for (final farm in farms) {
        if (MarketingService.samePhone(farm.phone, trimmed)) return farm;
      }
    }
    return farms.first;
  }

  /// The farm in [farms] holding [typed], ignoring dealers.
  ///
  /// A farm and a dealer may legitimately share a number — the same person can
  /// run a farm and trade as a dealer — and the server scopes its unique index
  /// the same way, so warning about a cross-pool clash would block a save the
  /// database would happily accept.
  static Party? sameFarmPhone(List<Party> farms, String typed) {
    for (final party in farms) {
      if (!party.isFarm) continue;
      if (MarketingService.samePhone(party.phone, typed)) return party;
    }
    return null;
  }

  /// The farms in [farms] matching [query], narrowed for the browse list.
  ///
  /// The list is held on the device and filtered here rather than re-fetched,
  /// so this runs on every keystroke — which is why it is static, pure, and
  /// why it avoids touching the widget tree.
  ///
  /// A phone-shaped query is compared by **digits first**, so typing a farm's
  /// exact number surfaces that farm at the top of the list rather than burying
  /// it among the farms whose phone merely contains those digits as a
  /// substring. The name / code contains pass still runs, so a number that
  /// matches nothing exactly does not produce an empty list.
  ///
  /// Under two characters everything is offered: a single letter matches half
  /// the catalogue and a list that appears to be broken is worse than a long one.
  static List<Party> filterFarms(List<Party> farms, String query) {
    final trimmed = query.trim();
    if (trimmed.length < 2) return farms;

    final lower = trimmed.toLowerCase();
    final exact = looksLikePhone(trimmed)
        ? farms
              .where((f) => MarketingService.samePhone(f.phone, trimmed))
              .toList()
        : const <Party>[];
    if (exact.isNotEmpty) return exact;

    return farms
        .where(
          (f) =>
              f.displayName.toLowerCase().contains(lower) ||
              (f.code ?? '').toLowerCase().contains(lower) ||
              (f.phone ?? '').toLowerCase().contains(lower),
        )
        .toList();
  }

  /// The trade name a farm is filed under.
  ///
  /// The farms report exports `name`, not `trade_name`, so a farm that only
  /// filled `name` would show blank there and anywhere else reading
  /// [Party.displayName], which prefers `tradeName`. Writing the same value to
  /// both columns is what makes "the farm name is the trade name" true in the
  /// data rather than only in the UI.
  ///
  /// Trimmed, and null when blank so the column stays NULL rather than holding
  /// an empty string.
  static String? tradeNameFor(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// The products belonging to [category], for a product row's picker.
  ///
  /// A null category means "not chosen yet", which offers the whole catalogue
  /// rather than nothing — the officer should be able to pick a product first
  /// and have the category follow, as long as the two are made consistent.
  ///
  /// Static and pure so the filter rule is testable without a widget.
  static List<MarketingDemoProduct> productsInCategory(
    List<MarketingDemoProduct> products,
    MarketingDemoNamed? category,
  ) {
    if (category == null) return products;
    return products.where((p) => p.categoryId == category.id).toList();
  }
}

class _FarmFormScreenState extends State<FarmFormScreen> {
  final MarketingService _service = MarketingService();
  final AuthService _authService = AuthService();

  final _name = TextEditingController();
  final _ownerName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _nid = TextEditingController();
  final _tradeLicense = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  final _capacity = TextEditingController();

  /// `party_type` is fixed. The officer reached this screen from the Farms tab,
  /// so the type is a fact about the record rather than a choice, and it rides
  /// in the payload without ever being rendered.
  static const String _partyType = 'farm';

  String _visitType = FarmFormScreen.defaultVisitType;
  String _farmType = FarmFormScreen.defaultFarmType;

  // ---------------------------------------------------------------------
  // Existing-farm lookup
  // ---------------------------------------------------------------------

  final _search = TextEditingController();
  final _searchFocusNode = FocusNode();

  /// True once the officer has touched the field. Tapping it lists the farms
  /// already on file; typing narrows that list. The flag is what keeps the
  /// screen from firing a list request the moment it opens, before the officer
  /// has shown any sign of wanting one.
  bool _browsing = false;
  bool _loadingFarms = false;
  bool _loadFailed = false;
  bool _farmsLoaded = false;

  /// Every farm in the employee's zones, fetched once and narrowed in Dart.
  List<Party> _zoneFarms = const [];

  /// The farm the officer picked out of the browse list, or the exact match the
  /// query landed on. Null means nothing is selected yet.
  Party? _selectedMatch;

  /// The detail fields are always visible. The search bar sits above them as a
  /// convenience for finding a farm already on file, not as a gate.
  bool _creating = true;

  /// The farm already holding the typed phone, from the on-field uniqueness
  /// check that keeps running after the form is revealed.
  Party? _phoneClash;

  /// --- Masters ---------------------------------------------------------

  /// The employee's own zone, resolved from their HRM profile. Shown read-only.
  MarketingDemoNamed? _employeeZone;

  /// Server-allocated `FMR-…`. Null until the endpoint answers, and left null on
  /// failure rather than invented locally — a code guessed on the device can
  /// collide, which is the whole reason it is allocated server-side.
  String? _generatedCode;

  /// Peoples Poultry & Hatchery Ltd, preselected.
  BookingFormCompany? _selectedCompany;
  List<BookingFormCompany> _companies = const [];

  /// The list of companies the *product* rows offer — the same
  /// live master the farm's own company picker uses, so the two
  /// can never disagree. The farm's own company comes from the
  /// officer's pick above.
  List<BookingFormCompany> _productCompanies = const [];

  List<Party> _dealers = const [];
  Party? _parentParty;
  MarketingDemoNamed? _capacityUnit;

  double? _lat;
  double? _lng;
  bool _loadingMasters = true;
  bool _loadingDealers = false;
  bool _resolvingLocation = true;
  String? _locationStatus;
  bool _submitting = false;
  final List<_FarmProductRow> _products = [];
  final List<XFile> _photos = [];

  static const _relationTypes = [
    'business',
    'uses',
    'sells',
    'stock',
    'demand',
    'competitor',
  ];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _loadFormMasters(),
      _autoFillLocation(),
      _loadOrgMasters(),
      _loadDealers(),
    ]);
  }

  /// Reserves the record code from the server.
  ///
  /// A failure is not fatal: the code is optional server-side, and a missing one
  /// is far better than a duplicate. The field then reads as unavailable rather
  /// than showing an empty box the officer might assume they can type into.
  Future<void> _loadCode() async {
    final result = await _service.nextCode('FMR');
    if (!mounted) return;
    setState(() {
      _generatedCode = result.success ? result.data : null;
    });
  }

  Future<void> _loadFormMasters() async {
    await Future.wait([
      _loadZone(),
      ZoneScopeService.instance.loadZoneOptions(),
    ]);
    if (!mounted) return;
    setState(() => _loadingMasters = false);
  }

  /// Resolves the employee's zone from their HRM profile.
  ///
  /// The zone is shown read-only on the form. It is a fact about who is filing
  /// the record, not a filter on anything the officer chooses.
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

  /// Loads the company list and preselects the farm's default company.
  ///
  /// Falls back to the first row when no name matches, because an officer who
  /// has to open a picker to find the only company the app trades under is an
  /// officer who will file the farm under the wrong one. A genuinely empty list
  /// leaves the selection null, and submit already blocks on that.
  Future<void> _loadOrgMasters() async {
    final companies = await MarketingMasterService.instance.companies();
    if (!mounted) return;
    setState(() {
      _companies = companies;
      _productCompanies = companies;
      _selectedCompany = FarmFormScreen.defaultCompany(companies);
    });
  }

  /// Loads the parent-dealer list. Company-wide — the picker is not narrowed by
  /// the employee's zone, because an officer who trades across a neighbouring
  /// zone still has to be able to record it.
  Future<void> _loadDealers() async {
    setState(() => _loadingDealers = true);
    final result = await _service.listParties(partyType: 'dealer');
    if (!mounted) return;
    setState(() {
      _dealers = result.data ?? const [];
      _loadingDealers = false;
    });
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _name.dispose();
    _ownerName.dispose();
    _phone.dispose();
    _email.dispose();
    _nid.dispose();
    _tradeLicense.dispose();
    _address.dispose();
    _notes.dispose();
    _capacity.dispose();
    _search.dispose();
    for (final p in _products) {
      p.dispose();
    }
    super.dispose();
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

  // ---------------------------------------------------------------------
  // Existing-farm lookup
  // ---------------------------------------------------------------------

  /// Opens the browse list on a tap, and keeps narrowing it as the officer types.
  ///
  /// The list is fetched **once** per screen rather than per keystroke: it is
  /// a bounded, zone-scoped set the device can hold, and a network round-trip
  /// between every character would make typing feel broken.
  void _onSearchChanged(String value) {
    if (!_browsing) {
      setState(() => _browsing = true);
      if (!_farmsLoaded) _loadZoneFarms();
      return;
    }
    // Narrowing is pure and synchronous, so the list responds on the same frame
    // as the keystroke. Only a previous selection is dropped — a farm the
    // officer already picked stays picked until they pick another or clear.
    setState(() => _selectedMatch = null);
  }

  /// Tapping the field with an empty box opens the same list as typing would.
  void _onSearchTap() {
    if (_browsing) return;
    setState(() => _browsing = true);
    if (!_farmsLoaded) _loadZoneFarms();
  }

  /// Fetches every farm the employee can see, once.
  Future<void> _loadZoneFarms() async {
    setState(() {
      _loadingFarms = true;
      _loadFailed = false;
    });

    final result = await _service.listFarms();
    if (!mounted) return;

    if (!result.success) {
      // A failed load is not an empty list. Offering to create a farm off a
      // network blip is how a duplicate gets filed, so the failure is surfaced
      // and the server's own uniqueness rule stays the authority.
      setState(() {
        _loadingFarms = false;
        _loadFailed = true;
        _farmsLoaded = true;
        _zoneFarms = const [];
      });
      return;
    }

    setState(() {
      _loadingFarms = false;
      _farmsLoaded = true;
      _zoneFarms = result.data ?? const <Party>[];
    });
  }

  /// The farms in the employee's zones, narrowed by what they have typed.
  List<Party> get _visibleFarms => FarmFormScreen.filterFarms(
    _zoneFarms,
    _search.text,
  );

  /// Commits to creating a farm, seeding the field the query really was.
  ///
  /// A digit run of at least [FarmFormScreen.minPhoneDigits] cannot be a farm
  /// name, so it goes to Phone; anything else goes to Name. The other field is
  /// left for the officer — guessing it would be inventing data.
  void _startCreating() {
    final typed = _search.text.trim();
    setState(() {
      _creating = true;
      // Close the lookup. The farm list was the way *into* this decision; once
      // it is made the list is the wrong thing to keep on screen, and leaving
      // it open would push the form the officer now has to fill in below a
      // scrollable panel they no longer need. The typed query stays in the
      // field, so it still reads as what they searched for and seeds the form.
      _browsing = false;
      _searchFocusNode.unfocus();
      // The first product row is seeded here rather than in initState: until the
      // officer commits, the product section is not rendered at all, and a row
      // built then would be a set of controllers nobody can type into.
      _products.add(_FarmProductRow());
      if (FarmFormScreen.looksLikePhone(typed)) {
        _phone.text = typed;
      } else if (typed.isNotEmpty) {
        _name.text = typed;
      }
    });
    if (FarmFormScreen.looksLikePhone(typed)) {
      _checkPhone();
    }
  }

  /// Clears the search and drops back to the search-only state.
  ///
  /// Also drops any product rows, because going back to search-only hides the
  /// section that owns them — leaving them alive would mean the next
  /// "Add new farm" starts with the previous attempt's rows still in it.
  void _resetSearch() {
    setState(() {
      for (final row in _products) {
        row.dispose();
      }
      _products.clear();
      _search.clear();
      _creating = false;
      _browsing = false;
      _loadFailed = false;
      _zoneFarms = const [];
      _farmsLoaded = false;
      _selectedMatch = null;
      _phoneClash = null;
    });
  }

  /// Opens the farm visit report for a farm that already exists.
  Future<void> _postVisit(Party farm) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FarmSurveyFormScreen(party: farm),
      ),
    );
  }

  /// Checks whether the typed phone already belongs to a farm.
  ///
  /// The backend `q` filter is a substring LIKE, so every hit is compared after
  /// `normalisePhone` — otherwise `+8801712…` would not be recognised as the same
  /// number as `01712…` and the duplicate would slip through.
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

    setState(() => _phoneClash =
        FarmFormScreen.sameFarmPhone(result.data ?? const <Party>[], typed));
  }

  void _onPhoneChanged() {
    _phoneClash = null;
    _checkPhone();
  }

  String? get _phoneError {
    final clash = _phoneClash;
    if (clash != null) {
      final code = clash.code;
      return 'Already linked to ${clash.displayName}'
          '${code != null && code.isNotEmpty ? ' ($code)' : ''}';
    }
    if (_phone.text.trim().isEmpty) return 'Phone is required.';
    return null;
  }

  // ---------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------

  Future<void> _submit() async {
    // Defence in depth: the create pill on the hub is already gated, so a user
    // without `farms.create` cannot reach this form by tapping. Re-checked here
    // because a stale navigation stack or a future deep link could still land
    // on it.
    if (!PermissionService.instance.canCreateIn('farm')) {
      _snack(PermissionService.instance.denialMessage('farm'));
      return;
    }
    if (_name.text.trim().isEmpty) {
      _snack('Farm name is required.');
      return;
    }
    if (_phone.text.trim().isEmpty) {
      _snack('Phone is required.');
      return;
    }

    // Re-check rather than trusting the on-change result: the officer may have
    // edited the number since, and the server is the real authority either way.
    await _checkPhone();
    if (!mounted) return;
    final clash = _phoneClash;
    if (clash != null) {
      // Surface the farm that already holds the number rather than only saying
      // no — the officer's next move is almost always to post a visit against
      // it, and that button is on the match panel.
      setState(() => _selectedMatch = clash);
      _snack('That phone number is already linked to another farm.');
      return;
    }

    // Every farm is filed under the employee's zone — the zone is what every
    // marketing list and report filters on, so an untagged farm is as
    // unreachable as an untagged dealer.
    if (_employeeZone == null) {
      _snack(
        'Your zone could not be resolved. Ask an admin to set your zone, then retry.',
      );
      return;
    }
    // Sector and market are gone from this form, so the company is the only
    // organisation left to file under.
    if (_selectedCompany == null) {
      _snack('Choose the company this farm belongs to.');
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

    // Reserve the record code now. It is only consumed when the form is actually
    // submitted, so merely opening the screen no longer burns a sequence number.
    await _loadCode();
    if (!mounted) return;

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
        'is_our_product': row.isOurProduct,
        if (row.notes.text.trim().isNotEmpty) 'notes': row.notes.text.trim(),
      });
    }

    final payload = <String, dynamic>{
      'employee_id': employeeId,
      'party_type': _partyType,
      'name': _name.text.trim(),
      // Written to both columns: the web farms report exports `name`, while
      // `Party.displayName` prefers `trade_name`, so filling only one of them
      // leaves the farm blank in one place or the other.
      'trade_name': FarmFormScreen.tradeNameFor(_name.text),
      // The server-allocated code wins over anything typed: the field is
      // read-only.
      if (_generatedCode != null && _generatedCode!.isNotEmpty)
        'code': _generatedCode,
      if (_ownerName.text.trim().isNotEmpty)
        'owner_name': _ownerName.text.trim(),
      if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
      if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
      if (_nid.text.trim().isNotEmpty) 'nid_no': _nid.text.trim(),
      if (_tradeLicense.text.trim().isNotEmpty)
        'trade_license_no': _tradeLicense.text.trim(),
      if (_address.text.trim().isNotEmpty) 'address': _address.text.trim(),
      if (_parentParty != null) 'parent_party_id': _parentParty!.id,
      if (_selectedCompany != null) 'company_id': _selectedCompany!.id,
      if (_selectedCompany != null)
        'company_name': _selectedCompany!.displayName,
      if (_employeeZone != null) 'zone_id': _employeeZone!.id,
      if (_employeeZone != null) 'zone_name': _employeeZone!.name,
      'visit_type': _visitType,
      'farm_type': _farmType,
      if (_capacity.text.trim().isNotEmpty)
        'capacity': double.tryParse(_capacity.text.trim()),
      if (_capacityUnit != null) 'capacity_unit_id': _capacityUnit!.id,
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
      _snack(result.message ?? 'Could not create farm.');
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
        _snack('Farm saved, but photo upload failed: ${upload.message}');
      }
    }

    if (!mounted) return;
    setState(() => _submitting = false);
    _snack('Saved successfully.');
    Navigator.of(context).pop(party);
  }

  Future<void> _pickPhotos() async {
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return;
    setState(() => _photos.addAll(files));
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------------------------------------------------------------
  // Chrome
  // ---------------------------------------------------------------------

  /// Shared input decoration.
  ///
  /// Caption for the next input, set by [_label] and consumed by [_decoration].
  ///
  /// These forms are read strictly top-to-bottom, so a caption always immediately
  /// precedes the field it names. That lets the caption move *inside* the field
  /// as a Material floating legend — shown as the placeholder, lifting above the
  /// input on focus or fill — instead of sitting as a separate line above it.
  /// [_sectionTitle] clears it so a section boundary can never leak a stale
  /// caption into the first field below.
  String? _pendingLabel;

  InputDecoration _decoration({String? label, String? hint, String? errorText}) {
    final legend = label ?? _pendingLabel ?? hint;
    _pendingLabel = null;
    return InputDecoration(
      labelText: legend,
      // Keep the inline hint only when it adds something the legend does not.
      hintText: hint == legend ? null : hint,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      errorText: errorText,
      filled: true,
      fillColor: AppColors.surfaceSunk,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  /// Caption for the next input. It no longer draws a line above the field — the
  /// text becomes that field's floating legend (see [_decoration]).
  Widget _label(String text) {
    _pendingLabel = text;
    return const SizedBox.shrink();
  }

  Widget _sectionTitle(String text) {
    // A section boundary resets any caption the previous section left pending.
    _pendingLabel = null;
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

  /// The search control at the top of the screen.
  ///
  /// A plain text field rather than a `SearchableSelectField`, because the list
  /// is fetched from the server and stays on the device to be narrowed locally —
  /// an overlay dropdown that re-queries on every keystroke would be the wrong
  /// shape for that.
  ///
  /// Read-only once the officer has committed to adding a farm. The field is
  /// then a record of what they searched for, not something they still need to
  /// edit — and the clear button has to go with it, because [_resetSearch]
  /// discards the whole form, not just the query.
  Widget _buildSearch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label('Search existing farm'),
        TextField(
          controller: _search,
          focusNode: _searchFocusNode,
          onTap: _onSearchTap,
          onChanged: _onSearchChanged,
          style: AppType.bodySm.copyWith(color: AppColors.ink),
          decoration: _decoration(
            hint: 'Tap to browse, or type a name or number',
          ).copyWith(
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _search.text.isEmpty
                ? const Icon(Icons.arrow_drop_down, size: 22)
                : IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: _resetSearch,
                  ),
          ),
        ),
        if (_browsing) _buildBrowseResults(),
      ],
    );
  }

  /// The farm list under the search field: loading, the zone's farms, the
  /// "nothing found" offer, or the load failure.
  Widget _buildBrowseResults() {
    if (_loadingFarms) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: LinearProgressIndicator(),
      );
    }

    if (_loadFailed) {
      return _searchNotice(
        icon: Icons.cloud_off_outlined,
        tone: AppColors.error,
        title: 'Could not load existing farms',
        detail: 'The server did not answer. You can still add the farm — a '
            'duplicate phone number is rejected on save.',
        action: TextButton(
          onPressed: _startCreating,
          child: const Text('Add new farm'),
        ),
      );
    }

    final match = _selectedMatch;
    if (match != null) return _buildMatchPanel(match);

    final farms = _visibleFarms;
    if (farms.isEmpty) {
      final query = _search.text.trim();
      return _searchNotice(
        icon: Icons.search_off_outlined,
        tone: AppColors.inkMuted,
        title: 'No farm found',
        detail: query.isEmpty
            ? 'No farms on file in your zone yet.'
            : 'Nothing in your zone matches "$query".',
        action: FilledButton.icon(
          onPressed: _startCreating,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add new farm'),
        ),
      );
    }

    return _buildFarmList(farms);
  }

  /// The zone's farms, each tappable, with the create action kept in reach.
  ///
  /// The header states how many farms are on file and carries the create button,
  /// so the officer can always add a farm without first having to type something
  /// that finds nothing — which is the case that happens most often in a zone
  /// where the farm being visited is genuinely new.
  Widget _buildFarmList(List<Party> farms) {
    final query = _search.text.trim();
    final total = _zoneFarms.length;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunk,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    query.isEmpty
                        ? '${farms.length} '
                              '${farms.length == 1 ? 'farm' : 'farms'} in your zone'
                        : '${farms.length} of $total '
                              '${total == 1 ? 'farm' : 'farms'} match',
                    style: AppType.meta.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _startCreating,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add new farm'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Capped so a zone with hundreds of farms cannot push the create
          // action and the rest of the screen off the bottom.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView.builder(
              shrinkWrap: true,
              primary: false,
              padding: EdgeInsets.zero,
              itemCount: farms.length,
              itemBuilder: (context, index) => _farmRow(farms[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _farmRow(Party farm) {
    final phone = farm.phone;
    final code = farm.code;

    return ListTile(
      dense: true,
      onTap: () => setState(() => _selectedMatch = farm),
      title: Text(farm.displayName, style: AppType.bodySm),
      subtitle: Text(
        [if (code != null && code.isNotEmpty) code, if (phone != null && phone.isNotEmpty) phone]
            .join(' · '),
        style: AppType.meta.copyWith(color: AppColors.inkMuted),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        size: 20,
        color: AppColors.inkFaint,
      ),
    );
  }

  /// The farm this search has landed on: what it is, and what to do about it.
  Widget _buildMatchPanel(Party farm) {
    final code = farm.code;
    final phone = farm.phone;
    final zone = farm.zoneName;

    return _searchNotice(
      icon: Icons.check_circle_outline,
      tone: AppColors.success,
      title: 'Farm already exists',
      detail: farm.name,
      action: null,
      extra: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (code != null && code.isNotEmpty) _matchLine(Icons.qr_code_2_outlined, code),
          if (phone != null && phone.isNotEmpty) _matchLine(Icons.phone_outlined, phone),
          if (zone != null && zone.isNotEmpty) _matchLine(Icons.map_outlined, zone),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _postVisit(farm),
                  icon: const Icon(Icons.assignment_outlined, size: 18),
                  label: const Text('Post a visit report'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: _resetSearch, child: const Text('Cancel')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _matchLine(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppColors.inkFaint),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: AppType.meta.copyWith(color: AppColors.inkMuted)),
          ),
        ],
      ),
    );
  }

  Widget _searchNotice({
    required IconData icon,
    required Color tone,
    required String title,
    required String detail,
    required Widget? action,
    Widget? extra,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: tone.withValues(alpha: 0.28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: tone),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppType.bodySm.copyWith(
                          fontWeight: FontWeight.w600,
                          color: tone,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: AppType.meta.copyWith(color: AppColors.inkMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (extra != null) ...[
              const SizedBox(height: 12),
              extra,
            ],
            if (action != null) ...[
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerLeft, child: action),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Column(
        children: [
          AppHeader(
            title: 'Add Farm',
            subtitle: 'Find an existing farm, or register a new one',
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppCard(child: _buildSearch()),
                  // Everything below is the form itself. It appears only once the
                  // officer has committed to adding a farm — the screen opens as
                  // a lookup, and an officer who has just found the farm they
                  // meant should not be looking at an empty product table and a
                  // photo picker they are about to discard.
                  if (_creating) ...[
                    const SizedBox(height: 12),
                    _buildFarmDetails(),
                    const SizedBox(height: 12),
                    _buildProducts(),
                    const SizedBox(height: 12),
                    _buildPhotosAndSubmit(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Everything after the search, revealed once the officer commits to adding.
  Widget _buildFarmDetails() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('Farm details'),
          _label('Visit type'),
          DropdownButtonFormField<String>(
            initialValue: _visitType,
            decoration: _decoration(),
            items: FarmFormScreen.visitTypes
                .map(
                  (t) => DropdownMenuItem(value: t.value, child: Text(t.label)),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _visitType = v);
            },
          ),
          const SizedBox(height: 14),
          // The zone is the officer's own territory and stays read-only: a fact
          // about who is filing the record, not a choice.
          if (_loadingMasters)
            const LinearProgressIndicator()
          else
            ReadOnlyField(
              label: 'Zone *',
              icon: Icons.map_outlined,
              value: _employeeZone?.name,
              hint: 'Not set — ask an admin to set your zone',
            ),
          const SizedBox(height: 14),
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
              searchText: (d) =>
                  '${d.displayName} ${d.phone ?? ''}'.toLowerCase(),
              subtitleFor: (d) => d.phone,
              onSelected: (d) => setState(() => _parentParty = d),
            ),
          const SizedBox(height: 14),
          // Allocated server-side so two officers opening this form at the same
          // moment cannot be handed the same code.
          ReadOnlyField(
            label: 'Farm code',
            icon: Icons.qr_code_2_outlined,
            value: _generatedCode,
            hint: _generatedCode == null ? 'Generated on save' : null,
          ),
          const SizedBox(height: 14),
          // The name and phone sit after the code on purpose: the code is the
          // record's identity and is already settled, so what follows is the
          // part the officer actually supplies. There is no separate trade
          // name — the farm name is written to both columns, so what the
          // officer types here is what every list and report shows.
          _label('Farm name *'),
          VoiceTextField(
            controller: _name,
            decoration: _decoration(hint: 'Farm name'),
          ),
          const SizedBox(height: 14),
          // A farm is looked up by phone, so the number is required and has to
          // belong to exactly one farm.
          _label('Phone *'),
          VoiceTextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            onChanged: (_) => _onPhoneChanged(),
            decoration: _decoration(errorText: _phoneError),
          ),
          const SizedBox(height: 14),
          SearchableSelectField<BookingFormCompany>(
            label: 'Company *',
            icon: Icons.apartment_outlined,
            options: _companies,
            selected: _selectedCompany,
            displayString: (c) => c.displayName,
            searchText: (c) => c.displayName.toLowerCase(),
            onSelected: (c) => setState(() => _selectedCompany = c),
          ),
          const SizedBox(height: 14),
          _label('Owner name'),
          VoiceTextField(
            controller: _ownerName,
            decoration: _decoration(hint: 'Owner / proprietor'),
          ),
          const SizedBox(height: 14),
          _label('Farm type'),
          DropdownButtonFormField<String>(
            initialValue: _farmType,
            decoration: _decoration(),
            items: FarmFormScreen.farmTypes
                .map(
                  (t) => DropdownMenuItem(value: t.value, child: Text(t.label)),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _farmType = v);
            },
          ),
          const SizedBox(height: 14),
          _label('Capacity'),
          VoiceTextField(
            controller: _capacity,
            keyboardType: TextInputType.number,
            decoration: _decoration(hint: 'Capacity'),
          ),
          const SizedBox(height: 14),
          SearchableSelectField<MarketingDemoNamed>(
            label: 'Capacity unit',
            icon: Icons.straighten,
            options: MarketingDemoMasters.units,
            selected: _capacityUnit,
            displayString: (u) => u.displayName,
            searchText: (u) => u.searchText,
            onSelected: (u) => setState(() => _capacityUnit = u),
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
          const SizedBox(height: 14),
          _label('Address'),
          VoiceTextField(
            controller: _address,
            maxLines: 2,
            decoration: _decoration(),
          ),
          if (_locationStatus != null) ...[
            const SizedBox(height: 12),
            Text(
              _locationStatus!,
              style: AppType.meta.copyWith(
                color: _resolvingLocation ? AppColors.inkFaint : AppColors.inkMuted,
              ),
            ),
            if (_resolvingLocation) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
          ],
          const SizedBox(height: 14),
          _label('Notes'),
          VoiceTextField(
            controller: _notes,
            maxLines: 2,
            decoration: _decoration(),
          ),
        ],
      ),
    );
  }

  Widget _buildProducts() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _sectionTitle('Products')),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _products.add(_FarmProductRow())),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          ...List.generate(_products.length, (i) {
            final row = _products[i];
            final categoryProducts = FarmFormScreen.productsInCategory(
              MarketingDemoMasters.products,
              row.category,
            );

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSunk,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Category first, because it narrows the product list
                    // directly beneath it. The reverse order would mean picking
                    // a product from the whole catalogue and then being told it
                    // does not belong to the category.
                    SearchableSelectField<MarketingDemoNamed>(
                      label: 'Product category',
                      icon: Icons.category_outlined,
                      options: MarketingDemoMasters.categories,
                      selected: row.category,
                      displayString: (c) => c.displayName,
                      searchText: (c) => c.searchText,
                      onSelected: (c) => setState(() {
                        row.category = c;
                        // A product from the old category would contradict the
                        // new one, so it is dropped rather than left to fail
                        // silently on submit.
                        if (row.product != null && c != null &&
                            row.product!.categoryId != c.id) {
                          row.product = null;
                        }
                      }),
                    ),
                    const SizedBox(height: 8),
                    SearchableSelectField<MarketingDemoProduct>(
                      label: 'Product',
                      icon: Icons.inventory_2_outlined,
                      options: categoryProducts,
                      selected: row.product,
                      enabled: true,
                      hintText: categoryProducts.isEmpty
                          ? 'No products in this category'
                          : 'Tap to pick or type…',
                      displayString: (p) => p.displayName,
                      searchText: (p) => p.searchText,
                      subtitleFor: (p) => p.categoryName,
                      onSelected: (p) {
                        setState(() {
                          row.product = p;
                          if (p != null) {
                            row.name.text = p.name;
                            row.isOurProduct = p.ourProduct;
                            row.category ??=
                                MarketingDemoMasters.byId(
                                  MarketingDemoMasters.categories,
                                  p.categoryId,
                                  (c) => c.id,
                                );
                            row.company = MarketingDemoMasters.byId(
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
                      decoration: _decoration(hint: 'Product name (required)'),
                    ),
                    const SizedBox(height: 8),
                    SearchableSelectField<BookingFormCompany>(
                      label: 'Product company',
                      icon: Icons.apartment_outlined,
                      options: _productCompanies,
                      selected: row.company,
                      displayString: (c) => c.displayName,
                      searchText: (c) => c.displayName.toLowerCase(),
                      onSelected: (c) => setState(() => row.company = c),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: row.relationType,
                      decoration: _decoration(hint: 'Relation type'),
                      items: _relationTypes
                          .map(
                            (t) => DropdownMenuItem(value: t, child: Text(t)),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => row.relationType = v);
                      },
                    ),
                    const SizedBox(height: 8),
                    SearchableSelectField<MarketingDemoNamed>(
                      label: 'Unit',
                      icon: Icons.straighten,
                      options: MarketingDemoMasters.units,
                      selected: row.unit,
                      displayString: (u) => u.displayName,
                      searchText: (u) => u.searchText,
                      onSelected: (u) => setState(() => row.unit = u),
                    ),
                    const SizedBox(height: 8),
                    VoiceTextField(
                      controller: row.brand,
                      decoration: _decoration(hint: 'Brand name'),
                    ),
                    const SizedBox(height: 8),
                    VoiceTextField(
                      controller: row.demand,
                      keyboardType: TextInputType.number,
                      decoration: _decoration(hint: 'Monthly product demand'),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Our product', style: AppType.bodySm),
                      value: row.isOurProduct,
                      onChanged: (v) => setState(() => row.isOurProduct = v),
                    ),
                    VoiceTextField(
                      controller: row.notes,
                      decoration: _decoration(hint: 'Product notes'),
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
    );
  }

  Widget _buildPhotosAndSubmit() {
    return AppCard(
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
                        onTap: () => setState(() => _photos.removeAt(e.key)),
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
    );
  }
}