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
import '../../services/permission_service.dart';
import '../../services/sales_service.dart';
import '../../services/zone_scope_service.dart';
import '../../utils/marketing_location_helper.dart';
import '../../widgets/searchable_select_field.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/voice_input_field.dart';
import 'dealer_visit_form_screen.dart';

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
  final _gelender = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  final _farmType = TextEditingController();
  final _capacity = TextEditingController();
  final _businessYears = TextEditingController();
  final _creditLimit = TextEditingController();

  String _partyType = 'dealer';

  /// Customer type and business type replace payment_mode and lead_status on
  /// the dealer form — searchable dropdowns instead of free-text enums.
  MarketingDemoNamed? _selectedCustomerType;
  MarketingDemoNamed? _selectedBusinessType;

  /// Existing-dealer lookup (search-first pattern).
  final _search = TextEditingController();
  final _searchFocusNode = FocusNode();
  bool _browsing = false;
  bool _creating = false;
  Party? _selectedMatch;

  /// The employee's own zone, resolved from their HRM profile and shown
  /// read-only. It is a fact about who is filing the record, not a filter on
  /// the choices below.
  MarketingDemoNamed? _employeeZone;

  /// Company and market, each chosen by the officer. Sectors are no longer
  /// picked on this screen — markets are listed directly, the officer picks one.
  BookingFormCompany? _selectedCompany;
  Market? _selectedMarket;
  List<BookingFormCompany> _companies = const [];
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

  /// Only the product rows still offer a company picker, and it
  /// offers the same live master the party's own company picker
  /// uses. The party's own company comes from the officer's
  /// selection.
  List<BookingFormCompany> _productCompanies = const [];
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
  /// Options for the customer-type searchable dropdown (replaces Payment mode).
  static final _customerTypeOptions = [
    MarketingDemoNamed(id: 1, name: 'dealer'),
    MarketingDemoNamed(id: 2, name: 'direct_farm'),
    MarketingDemoNamed(id: 3, name: 'others'),
    MarketingDemoNamed(id: 4, name: 'all'),
  ];

  /// Options for the business-type searchable dropdown (replaces Lead status).
  static final _businessTypeOptions = [
    MarketingDemoNamed(id: 1, name: 'chicks'),
    MarketingDemoNamed(id: 2, name: 'feed'),
    MarketingDemoNamed(id: 3, name: 'fish'),
    MarketingDemoNamed(id: 4, name: 'poultry_feed'),
    MarketingDemoNamed(id: 5, name: 'all'),
    MarketingDemoNamed(id: 6, name: 'others'),
  ];

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
      _loadDealers(),
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

  /// Loads the company list and the full market list. Sectors are no longer
  /// picked on this screen, so markets are fetched directly rather than
  /// narrowed by a sector cascade.
  Future<void> _loadOrgMasters() async {
    final companies = await MarketingMasterService.instance.companies();
    final markets = await MarketingMasterService.instance.marketsForSector(null);
    if (!mounted) return;
    setState(() {
      _companies = companies;
      _productCompanies = companies;
      _markets = markets;
    });
  }

  /// Company selection clears the market pick — they are independent choices,
  /// so the officer re-picks the market for the new company.
  Future<void> _onCompanySelected(BookingFormCompany? company) async {
    setState(() {
      _selectedCompany = company;
      _selectedMarket = null;
    });
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
    _searchFocusNode.dispose();
    _search.dispose();
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
    _gelender.dispose();
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

  // ---------------------------------------------------------------------
  // Existing-dealer lookup (search-first pattern, mirrors FarmFormScreen)
  // ---------------------------------------------------------------------

  /// Narrows [dealers] by what the officer has typed, with a phone-first pass.
  ///
  /// A phone-shaped query is compared by **digits first**, so typing a dealer's
  /// exact number surfaces that dealer at the top rather than burying it
  /// among substring hits. The name / code contains pass still runs, so a number
  /// that matches nothing exactly does not produce an empty list. Under two
  /// characters everything is offered: a single letter matches half the
  /// catalogue and a list that appears to be broken is worse than a long one.
  static List<Party> filterDealers(List<Party> dealers, String query) {
    final trimmed = query.trim();
    if (trimmed.length < 2) return dealers;

    final lower = trimmed.toLowerCase();

    if (MarketingService.normalisePhone(trimmed).length >= 7) {
      final exact = dealers
          .where((d) => MarketingService.samePhone(d.phone, trimmed))
          .toList();
      if (exact.isNotEmpty) return exact;
    }

    return dealers
        .where(
          (d) =>
              d.displayName.toLowerCase().contains(lower) ||
              (d.code ?? '').toLowerCase().contains(lower) ||
              (d.phone ?? '').toLowerCase().contains(lower),
        )
        .toList();
  }

  /// The currently visible dealers in the browse list.
  List<Party> get _visibleDealers =>
      filterDealers(_dealers, _search.text);

  /// Opens the browse list on a tap, and keeps narrowing it as the officer
  /// types. Only a previous selection is dropped — a dealer the officer
  /// already picked stays picked until they pick another or clear.
  void _onSearchChanged(String value) {
    if (_creating) return;
    if (!_browsing) {
      setState(() => _browsing = true);
      return;
    }
    setState(() => _selectedMatch = null);
  }

  /// Tapping the field with an empty box opens the same list as typing would.
  void _onSearchTap() {
    if (_browsing || _creating) return;
    setState(() => _browsing = true);
  }

  /// Commits to creating a new dealer, seeding the field the query really was.
  ///
  /// A digit run of at least 7 cannot be a dealer name, so it goes to Phone;
  /// anything else goes to Dealer name. The other field is left for the officer.
  void _startCreating() {
    final typed = _search.text.trim();
    setState(() {
      _creating = true;
      _browsing = false;
      _searchFocusNode.unfocus();
      if (MarketingService.normalisePhone(typed).length >= 7) {
        _phone.text = typed;
      } else if (typed.isNotEmpty) {
        _name.text = typed;
      }
    });
    if (MarketingService.normalisePhone(typed).length >= 7) {
      _checkPhone();
    }
  }

  /// Clears the search and drops back to the search-only state. Also drops any
  /// product rows, because going back to search-only hides the section that owns
  /// them — leaving them alive would mean the next "Add new dealer" starts with
  /// the previous attempt's rows still in it.
  void _resetSearch() {
    setState(() {
      for (final row in _products) {
        row.dispose();
      }
      _products.clear();
      _search.clear();
      _creating = false;
      _browsing = false;
      _selectedMatch = null;
      _phoneClash = null;
    });
  }

  /// Opens the dealer visit report for a dealer that already exists.
  Future<void> _postVisit(Party dealer) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DealerVisitFormScreen(party: dealer),
      ),
    );
  }

  /// Formats a backend enum value into a human-readable label, e.g.
  /// `direct_farm` → `Direct farm`.
  static String _formatOption(String value) => value
          .replaceAll('_', ' ')
          .split(' ')
          .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');

  /// The top search bar. In search-only mode it filters the browse list; once
  /// the officer commits it becomes read-only and acts as a reminder of what
  /// was looked up.
  Widget _buildSearch() {
    final hasMatch = _selectedMatch != null;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _search,
            focusNode: _searchFocusNode,
            readOnly: _creating,
            decoration: InputDecoration(
              hintText: hasMatch
                  ? 'Dealer found — tap "Add new dealer" to create a new one'
                  : 'Search by name, code or phone…',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: _search.text.isEmpty
                  ? const Icon(Icons.arrow_drop_down, size: 22)
                  : (_creating
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: _resetSearch,
                        )),
            ),
            onChanged: _onSearchChanged,
            onTap: _onSearchTap,
          ),
          if (_creating) ...[
            const SizedBox(height: 8),
            _searchNotice(
              icon: Icons.info_outline,
              text: 'A new dealer will be created. Existing dealers can be '
                  'found by tapping "Cancel" and searching again.',
            ),
          ],
        ],
      ),
    );
  }

  /// Browse results or match panel shown below the search bar.
  Widget _buildBrowseCard() {
    if (_selectedMatch != null) {
      return AppCard(child: _buildMatchPanel());
    }
    if ((!_browsing && _dealers.isEmpty && !_loadingDealers) || _creating) {
      return const SizedBox.shrink();
    }
    return AppCard(child: _buildBrowseResults());
  }

  /// The filtered dealer list, with a notice for empty or loading states.
  Widget _buildBrowseResults() {
    if (_loadingDealers) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final visible = _visibleDealers;
    if (visible.isEmpty) {
      final query = _search.text.trim();
      return _searchNotice(
        icon: Icons.search_off,
        text: query.isEmpty
            ? 'No dealers have been recorded yet.'
            : 'No dealers match "$query".',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            '${visible.length} dealer${visible.length == 1 ? '' : 's'} found',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.inkMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: visible.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) => _dealerRow(visible[i]),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextButton.icon(
            onPressed: _startCreating,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add new dealer'),
          ),
        ),
      ],
    );
  }

  /// A single row in the browse list.
  Widget _dealerRow(Party dealer) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.primary.withValues(alpha: 0.15),
        child: const Icon(Icons.storefront_outlined, color: AppColors.primary),
      ),
      title: Text(
        dealer.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${dealer.code ?? ''} • ${dealer.phone ?? ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () {
        setState(() => _selectedMatch = dealer);
        _searchFocusNode.unfocus();
      },
    );
  }

  /// Panel shown when a dealer match is tapped — shows what was found and
  /// offers a visit report or the option to create a new one anyway.
  Widget _buildMatchPanel() {
    final match = _selectedMatch!;
    final code = match.code;
    final phone = match.phone;
    final zone = match.zoneName;
    final market = match.marketName;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            match.displayName,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          if (code != null && code.isNotEmpty)
            _matchLine(Icons.qr_code_2_outlined, 'Code: $code'),
          if (phone != null && phone.isNotEmpty)
            _matchLine(Icons.phone_outlined, 'Phone: $phone'),
          if (market != null && market.isNotEmpty)
            _matchLine(Icons.store_mall_directory, 'Market: $market'),
          if (zone != null && zone.isNotEmpty)
            _matchLine(Icons.map_outlined, 'Zone: $zone'),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextButton.icon(
                onPressed: () => _postVisit(match),
                icon: const Icon(Icons.post_add),
                label: const Text('Post a visit report'),
              ),
              TextButton.icon(
                onPressed: _resetSearch,
                icon: const Icon(Icons.refresh),
                label: const Text('Cancel'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _startCreating,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add new dealer'),
          ),
        ],
      ),
    );
  }

  Widget _matchLine(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 15, color: AppColors.inkMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.inkMuted,
                ),
              ),
            ),
          ],
        ),
      );

  /// A thin coloured banner used for notices inside the search flow.
  Widget _searchNotice({IconData? icon, required String text}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    // Defence in depth: the create pill on the hub is already gated, so a user
    // without `farms.create` / `dealer.create` cannot reach this form by
    // tapping. Re-checked here because a stale navigation stack or a future
    // deep link could still land on it.
    final moduleKey = _isFarm ? 'farm' : 'dealer';
    if (!PermissionService.instance.canCreateIn(moduleKey)) {
      _snack(PermissionService.instance.denialMessage(moduleKey));
      return;
    }
    if (_name.text.trim().isEmpty) {
      _snack('Dealer name is required.');
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
      if (_gelender.text.trim().isNotEmpty)
        'gelender': _gelender.text.trim(),
      if (_address.text.trim().isNotEmpty) 'address': _address.text.trim(),
      // The zone is the employee's own and is filed as-is. Company and market
      // are the officer's picks, sent with both the id and the name so the webapp
      // reports can read them without a master to join against. Sector is no
      // longer chosen on this screen.
      if (_selectedMarket != null) 'market_id': _selectedMarket!.id,
      if (_isFarm && _parentParty != null) 'parent_party_id': _parentParty!.id,
      if (_selectedExistingDealer != null)
        'existing_dealer_id': _selectedExistingDealer!.sourceId,
      if (_selectedCompany != null) 'company_id': _selectedCompany!.id,
      if (_selectedCompany != null)
        'company_name': _selectedCompany!.displayName,
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
      if (_selectedCustomerType != null)
        'customer_type': _selectedCustomerType!.name,
      if (_selectedBusinessType != null)
        'business_type': _selectedBusinessType!.name,
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
    if (!_creating) {
      return Scaffold(
        backgroundColor: AppColors.canvas,
        body: Column(
          children: [
            AppHeader(
              title: 'Add Dealer',
              subtitle: 'Search for an existing dealer, or add a new one',
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
                    AppCard(child: _buildSearch()),
                    const SizedBox(height: 12),
                    _buildBrowseCard(),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // The form reveals only once the officer commits to creating or the
    // screen is told up-front that _creating is true. The search bar stays
    // visible above the form as a read-only reminder of what was looked up.
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Column(
        children: [
          AppHeader(
            title: 'New Dealer',
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
                  AppCard(child: _buildSearch()),
                  const SizedBox(height: 12),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionTitle('Details'),
                        // The party-type picker is dealer-specific — the farm
                        // form lives in FarmFormScreen. Only the two
                        // business-meaningful dealer types are offered here.
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
                              if (v != 'outlet') {
                                _selectedExistingDealer = null;
                              }
                            });
                            if (v == 'outlet' && _existingDealers.isEmpty) {
                              _loadExistingDealers();
                            }
                          },
                        ),
                        const SizedBox(height: 14),
                        // The existing ERP dealer picker appears only for the
                        // existing-dealer type. A new dealer has no ERP dealer
                        // to attach, so showing an always-visible field there
                        // just invited an officer to file a dealer against a
                        // demo row.
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
                        // Allocated server-side so two officers opening this form
                        // at the same moment cannot be handed the same code.
                        ReadOnlyField(
                          label: 'Dealer code',
                          icon: Icons.qr_code_2_outlined,
                          value: _generatedCode,
                          hint: _loadingCode
                              ? 'Generating…'
                              : 'Unavailable — will save without one',
                        ),
                        const SizedBox(height: 14),
                        // The zone is the officer's own territory and stays
                        // read-only. Company and market are theirs to pick
                        // independently — sectors are no longer chosen on this
                        // screen.
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
                          SearchableSelectField<Market>(
                            label: 'Market',
                            icon: Icons.store_mall_directory_outlined,
                            options: _markets,
                            selected: _selectedMarket,
                            displayString: (m) => m.displayName,
                            searchText: (m) =>
                                '${m.name} ${m.locationLine}'.toLowerCase(),
                            subtitleFor: (m) =>
                                m.locationLine.isEmpty ? null : m.locationLine,
                            onSelected: (m) =>
                                setState(() => _selectedMarket = m),
                          ),
                          const SizedBox(height: 14),
                          _label('Dealer name *'),
                          VoiceTextField(
                            controller: _name,
                            decoration: _decoration(hint: 'Dealer name'),
                          ),
                          const SizedBox(height: 14),
                          _label('Trade name'),
                          VoiceTextField(
                            controller: _tradeName,
                            decoration: _decoration(hint: 'Optional'),
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
                        _label('Email'),
                        VoiceTextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 14),
                        _label('Gelender'),
                        VoiceTextField(
                          controller: _gelender,
                          decoration: _decoration(
                            hint: 'Known person / introducer',
                          ),
                        ),
                        const SizedBox(height: 14),
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
                        SearchableSelectField<MarketingDemoNamed>(
                          label: 'Customer type',
                          icon: Icons.category_outlined,
                          options: _customerTypeOptions,
                          selected: _selectedCustomerType,
                          displayString: (c) => _formatOption(c.name),
                          searchText: (c) => c.name.toLowerCase(),
                          onSelected: (v) =>
                              setState(() => _selectedCustomerType = v),
                        ),
                        const SizedBox(height: 14),
                        SearchableSelectField<MarketingDemoNamed>(
                          label: 'Business type',
                          icon: Icons.business_outlined,
                          options: _businessTypeOptions,
                          selected: _selectedBusinessType,
                          displayString: (c) => _formatOption(c.name),
                          searchText: (c) => c.name.toLowerCase(),
                          onSelected: (v) =>
                              setState(() => _selectedBusinessType = v),
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
