import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/theme.dart';
import '../../data/marketing_demo_masters.dart';
import '../../models/booking_form_data_models.dart';
import '../../models/marketing_models.dart';
import '../../services/auth_service.dart';
import '../../services/marketing_service.dart';
import '../../services/sales_service.dart';
import '../../utils/marketing_location_helper.dart';
import '../../widgets/gradient_screen_header.dart';
import '../../widgets/searchable_select_field.dart';
import '../../widgets/section_card.dart';

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
  List<Market> _markets = const [];
  List<Party> _dealers = const [];
  List<BookingFormCompany> _companies = MarketingDemoMasters.companies;
  List<BookingFormSector> _sectors = MarketingDemoMasters.sectors;
  Market? _selectedMarket;
  Party? _parentParty;
  BookingFormCompany? _selectedCompany;
  BookingFormSector? _selectedSector;
  MarketingDemoNamed? _existingDealer;
  MarketingDemoNamed? _capacityUnit;
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

  bool get _isFarm =>
      _partyType == 'farm' || _partyType == 'farmer';

  List<BookingFormSector> get _sectorsForCompany {
    if (_selectedCompany == null) return _sectors;
    final filtered =
        _sectors.where((s) => s.companyId == _selectedCompany!.id).toList();
    return filtered.isNotEmpty ? filtered : _sectors;
  }

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
        _companies = MarketingDemoMasters.companiesOr(result.data!.companies);
        _sectors = MarketingDemoMasters.sectorsOr(result.data!.sectors);
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
      if (_tradeName.text.trim().isNotEmpty) 'trade_name': _tradeName.text.trim(),
      if (_code.text.trim().isNotEmpty) 'code': _code.text.trim(),
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
      if (_selectedMarket != null) 'market_id': _selectedMarket!.id,
      if (_isFarm && _parentParty != null) 'parent_party_id': _parentParty!.id,
      if (_existingDealer != null) 'existing_dealer_id': _existingDealer!.id,
      if (_selectedCompany != null) 'company_id': _selectedCompany!.id,
      if (_selectedSector != null) 'sector_id': _selectedSector!.id,
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
                              if (!_isFarm) _parentParty = null;
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
                        _label('Code'),
                        TextField(
                          controller: _code,
                          decoration: _decoration(hint: 'Party code'),
                        ),
                        const SizedBox(height: 14),
                        SearchableSelectField<MarketingDemoNamed>(
                          label: 'Existing ERP dealer',
                          icon: Icons.storefront_outlined,
                          options: MarketingDemoMasters.dealers,
                          selected: _existingDealer,
                          displayString: (d) => d.displayName,
                          searchText: (d) => d.searchText,
                          subtitleFor: (d) => d.subtitle,
                          onSelected: (d) =>
                              setState(() => _existingDealer = d),
                        ),
                        const SizedBox(height: 14),
                        if (_loadingMasters)
                          const LinearProgressIndicator()
                        else ...[
                          SearchableSelectField<BookingFormCompany>(
                            label: 'Company',
                            icon: Icons.apartment_outlined,
                            options: _companies,
                            selected: _selectedCompany,
                            displayString: (c) => c.displayName,
                            searchText: (c) => c.displayName.toLowerCase(),
                            onSelected: (c) => setState(() {
                              _selectedCompany = c;
                              if (_selectedSector != null &&
                                  c != null &&
                                  _selectedSector!.companyId != null &&
                                  _selectedSector!.companyId != c.id) {
                                _selectedSector = null;
                              }
                            }),
                          ),
                          const SizedBox(height: 14),
                          SearchableSelectField<BookingFormSector>(
                            label: 'Sector',
                            icon: Icons.hub_outlined,
                            options: _sectorsForCompany,
                            selected: _selectedSector,
                            displayString: (s) => s.name,
                            searchText: (s) => s.searchText,
                            onSelected: (s) =>
                                setState(() => _selectedSector = s),
                          ),
                        ],
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
                        _label('Owner name'),
                        TextField(
                          controller: _ownerName,
                          decoration: _decoration(hint: 'Owner / proprietor'),
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
                        TextField(
                          controller: _businessYears,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 14),
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
                          SearchableSelectField<Market>(
                            label: 'Market',
                            icon: Icons.store_mall_directory_outlined,
                            options: _markets,
                            selected: _selectedMarket,
                            displayString: (m) => m.displayName,
                            searchText: (m) => m.displayName.toLowerCase(),
                            onSelected: (m) =>
                                setState(() => _selectedMarket = m),
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
                                            _companies,
                                            p.companyId,
                                            (c) => c.id,
                                          );
                                        }
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: row.name,
                                    decoration: _decoration(
                                      hint: 'Product name (required)',
                                    ),
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
                                    options: _companies,
                                    selected: row.company,
                                    displayString: (c) => c.displayName,
                                    searchText: (c) =>
                                        c.displayName.toLowerCase(),
                                    onSelected: (c) =>
                                        setState(() => row.company = c),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: row.brand,
                                    decoration:
                                        _decoration(hint: 'Brand name'),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: row.demand,
                                          keyboardType: TextInputType.number,
                                          decoration: _decoration(
                                            hint: 'Monthly / demand',
                                          ),
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
                                    controller: row.unitPrice,
                                    keyboardType: TextInputType.number,
                                    decoration:
                                        _decoration(hint: 'Unit price'),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
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
                                      style: GoogleFonts.poppins(fontSize: 13),
                                    ),
                                    value: row.isOurProduct,
                                    onChanged: (v) =>
                                        setState(() => row.isOurProduct = v),
                                  ),
                                  TextField(
                                    controller: row.notes,
                                    decoration:
                                        _decoration(hint: 'Product notes'),
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
