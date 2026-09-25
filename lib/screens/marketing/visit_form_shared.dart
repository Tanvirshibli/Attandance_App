import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../config/theme.dart';
import '../../data/marketing_demo_masters.dart';
import '../../models/marketing_models.dart';
import '../../services/auth_service.dart';
import '../../services/marketing_service.dart';
import '../../services/sales_service.dart';
import '../../utils/marketing_location_helper.dart';
import '../../widgets/gradient_screen_header.dart';
import '../../widgets/marketing_photo_widgets.dart';
import '../../widgets/searchable_select_field.dart';
import '../../widgets/searchable_text_field.dart';
import '../../widgets/section_card.dart';
import '../../widgets/voice_input_field.dart';
import 'visit_detail_screen.dart';

/// Visit types for dealer visits (farm surveys use a separate form).
const kPartyVisitTypes = [
  'regular',
  'order',
  'collection',
  'technical_support',
  'complaint',
  'dealer_opening',
  'other',
];

const kObservationTypes = [
  'uses',
  'sells',
  'stock',
  'demand',
  'order',
  'competitor',
  'sample',
  'price',
  'other',
];

const kDealerObservationTypes = [
  'stock',
  'order',
  'demand',
  'price',
  'competitor',
  'other',
];

String displayVisitType(String value) => value.replaceAll('_', ' ');

String normalizeVisitType(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return 'regular';
  final compact = trimmed.toLowerCase().replaceAll(' ', '_');
  for (final t in kPartyVisitTypes) {
    if (t == compact || displayVisitType(t) == trimmed.toLowerCase()) {
      return t;
    }
  }
  return compact;
}

List<String> get kPartyVisitTypeLabels =>
    kPartyVisitTypes.map(displayVisitType).toList();

class VisitObsRow {
  final name = TextEditingController();
  final brand = TextEditingController();
  final competitor = TextEditingController();
  final stock = TextEditingController();
  final demand = TextEditingController();
  final quantity = TextEditingController();
  final order = TextEditingController();
  final price = TextEditingController();
  final amount = TextEditingController();
  final notes = TextEditingController();
  String observationType = 'stock';
  MarketingDemoProduct? product;
  MarketingDemoNamed? unit;

  void Function()? _amountListener;
  bool _amountDealerMode = false;
  bool _computingAmount = false;

  void attachAmountListeners(bool dealerMode) {
    detachAmountListeners();
    _amountDealerMode = dealerMode;
    _amountListener = () {
      if (_computingAmount) return;
      _computingAmount = true;
      if (dealerMode) {
        final o = double.tryParse(order.text.trim());
        final p = double.tryParse(price.text.trim());
        if (o != null && p != null) {
          amount.text = (o * p).toStringAsFixed(2);
        } else {
          amount.clear();
        }
      } else {
        final q = double.tryParse(quantity.text.trim());
        final p = double.tryParse(price.text.trim());
        if (q != null && p != null) {
          amount.text = (q * p).toStringAsFixed(2);
        } else {
          amount.clear();
        }
      }
      _computingAmount = false;
    };
    if (dealerMode) {
      order.addListener(_amountListener!);
      price.addListener(_amountListener!);
    } else {
      quantity.addListener(_amountListener!);
      price.addListener(_amountListener!);
    }
  }

  void detachAmountListeners() {
    final listener = _amountListener;
    if (listener == null) return;
    if (_amountDealerMode) {
      order.removeListener(listener);
      price.removeListener(listener);
    } else {
      quantity.removeListener(listener);
      price.removeListener(listener);
    }
    _amountListener = null;
  }

  void dispose() {
    detachAmountListeners();
    name.dispose();
    brand.dispose();
    competitor.dispose();
    stock.dispose();
    demand.dispose();
    quantity.dispose();
    order.dispose();
    price.dispose();
    amount.dispose();
    notes.dispose();
  }
}

/// Dealer visit form — market/company/sector/zone autofill from the party,
/// required photo, and split feed/chicks findings.
class SharedVisitFormScreen extends StatefulWidget {
  const SharedVisitFormScreen.dealer({super.key, required this.party});

  final Party? party;

  @override
  State<SharedVisitFormScreen> createState() => _SharedVisitFormScreenState();
}

class _SharedVisitFormScreenState extends State<SharedVisitFormScreen> {
  final MarketingService _service = MarketingService();
  final AuthService _authService = AuthService();
  final SalesService _salesService = SalesService();
  final _objective = TextEditingController();
  final _findings = TextEditingController();
  final _feedFindings = TextEditingController();
  final _chicksFindings = TextEditingController();
  final _result = TextEditingController();
  final _nextPlan = TextEditingController();
  final _notes = TextEditingController();
  final _orderAmount = TextEditingController();
  final _collectionAmount = TextEditingController();
  final _visitType = TextEditingController(text: 'regular');

  List<Market> _markets = const [];
  List<BookingFormCompany> _companies = MarketingDemoMasters.companies;
  List<BookingFormSector> _sectors = MarketingDemoMasters.sectors;
  List<MarketingDemoProduct> _catalogProducts = MarketingDemoMasters.products;
  Market? _selectedMarket;
  Party? _selectedParty;
  BookingFormCompany? _selectedCompany;
  BookingFormSector? _selectedSector;
  int? _zoneId;
  String? _zoneName;
  DateTime? _nextVisitDate;
  double? _lat;
  double? _lng;
  bool _geoVerified = false;
  late final String _clientUuid;
  bool _loadingMarkets = true;
  bool _resolvingLocation = true;
  String? _locationStatus;
  bool _submitting = false;
  bool _checkingOut = false;
  Visit? _savedVisit;
  final List<VisitObsRow> _products = [VisitObsRow()];
  final List<XFile> _photos = [];

  bool get _locked => _savedVisit != null;

  String get _headerTitle {
    if (_locked) return 'Visit in progress';
    return 'Dealer visit';
  }

  String get _headerSubtitle => widget.party!.displayName;

  @override
  void initState() {
    super.initState();
    _clientUuid = marketingNewClientUuid();
    _selectedParty = widget.party;
    _zoneId = widget.party?.zoneId;
    _zoneName = widget.party?.zoneName;
    _loadMarkets();
    _loadMasters();
    _autoFillLocation();
    for (final row in _products) {
      row.attachAmountListeners(true);
    }
  }

  @override
  void dispose() {
    _objective.dispose();
    _findings.dispose();
    _feedFindings.dispose();
    _chicksFindings.dispose();
    _result.dispose();
    _nextPlan.dispose();
    _notes.dispose();
    _orderAmount.dispose();
    _collectionAmount.dispose();
    _visitType.dispose();
    for (final p in _products) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _loadMarkets() async {
    final result = await _service.listMarkets(zoneId: _zoneId);
    if (!mounted) return;
    setState(() {
      _markets = result.data ?? const [];
      _loadingMarkets = false;
      _selectedMarket = MarketingDemoMasters.byId(
        _markets,
        widget.party!.marketId,
        (m) => m.id,
      );
      // A market's zone is a good fallback when the party itself has none.
      if (_zoneId == null && _selectedMarket?.zoneId != null) {
        _zoneId = _selectedMarket!.zoneId;
        _zoneName = _selectedMarket!.zoneName;
      }
    });
  }

  Future<void> _loadMasters() async {
    final result = await _salesService.fetchBookingFormData();
    if (!mounted) return;
    setState(() {
      if (result.success && result.data != null) {
        _companies = MarketingDemoMasters.companiesOr(result.data!.companies);
        _sectors = MarketingDemoMasters.sectorsOr(result.data!.sectors);
        _catalogProducts =
            MarketingDemoMasters.productsFromBookingForm(result.data);
      }
      // Autofill company/sector from the party (dealer info).
      final party = widget.party;
      if (party != null) {
        _selectedCompany ??= MarketingDemoMasters.byId(
          _companies,
          party.companyId,
          (c) => c.id,
        );
        _selectedSector ??= MarketingDemoMasters.byId(
          _sectors,
          party.sectorId,
          (s) => s.id,
        );
        // Dealer zone name fallback: match against sales/booking zones.
        if (_zoneId == null && party.zoneId != null) {
          _zoneId = party.zoneId;
          _zoneName = party.zoneName;
        }
      }
    });
  }

  Future<void> _autoFillLocation() async {
    setState(() {
      _resolvingLocation = true;
      _locationStatus = 'Detecting check-in locationâ€¦';
    });
    try {
      final snap = await MarketingLocationHelper.capture();
      if (!mounted) return;
      if (snap == null) {
        setState(() {
          _resolvingLocation = false;
          _locationStatus =
              'Location unavailable â€” will retry on start visit.';
        });
        return;
      }
      setState(() {
        _lat = snap.latitude;
        _lng = snap.longitude;
        _geoVerified = true;
        _resolvingLocation = false;
        _locationStatus =
            'Check-in location ready (${snap.latitude.toStringAsFixed(5)}, ${snap.longitude.toStringAsFixed(5)})';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resolvingLocation = false;
        _locationStatus = 'Location failed â€” will retry on start visit.';
      });
      _snack('Could not get location: $e');
    }
  }

  Future<void> _ensureCheckInCoords() async {
    if (_lat != null && _lng != null) return;
    final snap = await MarketingLocationHelper.capture();
    if (snap == null) {
      _snack('Location permission required for check-in.');
      return;
    }
    _lat = snap.latitude;
    _lng = snap.longitude;
    _geoVerified = true;
  }

  Future<void> _pickPhotos() async {
    final files = await ImagePicker().pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return;
    setState(() => _photos.addAll(files));
  }

  Future<void> _pickNextVisitDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextVisitDate ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _nextVisitDate = picked);
  }

  Future<void> _submit() async {
    final party = _selectedParty;
    if (party == null) {
      _snack('Select a party to visit.');
      return;
    }
    if (_photos.isEmpty) {
      _snack('Add at least one photo to start the visit.');
      return;
    }

    final profile = await _authService.getCurrentUserProfile();
    final employeeId = profile?.canonicalEmployeeId;
    if (employeeId == null || employeeId <= 0) {
      _snack('Employee profile not linked.');
      return;
    }

    setState(() => _submitting = true);
    await _ensureCheckInCoords();

    final products = <Map<String, dynamic>>[];
    for (final row in _products) {
      var name = row.name.text.trim();
      if (name.isEmpty && row.product != null) name = row.product!.name;
      if (name.isEmpty) continue;
      products.add({
        'product_name': name,
        'observation_type': row.observationType,
        if (row.product != null) 'product_id': row.product!.id,
        if (row.unit != null) 'unit_id': row.unit!.id,
        if (row.unit != null) 'unit': row.unit!.name,
        if (row.brand.text.trim().isNotEmpty) 'brand_name': row.brand.text.trim(),
        if (row.competitor.text.trim().isNotEmpty)
          'competitor_company': row.competitor.text.trim(),
        if (row.quantity.text.trim().isNotEmpty)
          'quantity': double.tryParse(row.quantity.text.trim()),
        if (row.demand.text.trim().isNotEmpty)
          'demand_quantity': double.tryParse(row.demand.text.trim()),
        if (row.stock.text.trim().isNotEmpty)
          'stock_quantity': double.tryParse(row.stock.text.trim()),
        if (row.stock.text.trim().isNotEmpty)
          'observed_stock': double.tryParse(row.stock.text.trim()),
        if (row.order.text.trim().isNotEmpty)
          'order_qty': double.tryParse(row.order.text.trim()),
        if (row.price.text.trim().isNotEmpty)
          'unit_price': double.tryParse(row.price.text.trim()),
        if (row.price.text.trim().isNotEmpty)
          'price': double.tryParse(row.price.text.trim()),
        if (row.amount.text.trim().isNotEmpty)
          'amount': double.tryParse(row.amount.text.trim()),
        if (row.notes.text.trim().isNotEmpty) 'notes': row.notes.text.trim(),
      });
    }

    final now = DateTime.now();
    final objective = _objective.text.trim();
    final resultText = _result.text.trim();
    final visitType = normalizeVisitType(_visitType.text);
    final payload = <String, dynamic>{
      'party_id': party.id,
      'employee_id': employeeId,
      'visit_date': DateFormat('yyyy-MM-dd').format(now),
      'visit_type': visitType,
      'client_uuid': _clientUuid,
      'geo_verified': _geoVerified,
      if (_selectedMarket != null) 'market_id': _selectedMarket!.id,
      if (_selectedCompany != null) 'company_id': _selectedCompany!.id,
      if (_selectedSector != null) 'sector_id': _selectedSector!.id,
      if (_zoneId != null && _zoneId! > 0) 'zone_id': _zoneId,
      if (_zoneName != null && _zoneName!.isNotEmpty) 'zone_name': _zoneName,
      'check_in_at': now.toIso8601String(),
      if (_lat != null) 'check_in_lat': _lat,
      if (_lng != null) 'check_in_lng': _lng,
      if (objective.isNotEmpty) 'objective': objective,
      if (objective.isNotEmpty && objective.length <= 120) 'purpose': objective,
      if (_findings.text.trim().isNotEmpty) 'findings': _findings.text.trim(),
      if (_feedFindings.text.trim().isNotEmpty)
        'feed_findings': _feedFindings.text.trim(),
      if (_chicksFindings.text.trim().isNotEmpty)
        'chicks_findings': _chicksFindings.text.trim(),
      if (resultText.isNotEmpty) 'result': resultText,
      if (resultText.isNotEmpty && resultText.length <= 120)
        'outcome': resultText,
      if (_nextPlan.text.trim().isNotEmpty) 'next_plan': _nextPlan.text.trim(),
      if (_nextVisitDate != null)
        'next_visit_date': DateFormat('yyyy-MM-dd').format(_nextVisitDate!),
      if (_orderAmount.text.trim().isNotEmpty)
        'order_amount': double.tryParse(_orderAmount.text.trim()),
      if (_collectionAmount.text.trim().isNotEmpty)
        'collection_amount': double.tryParse(_collectionAmount.text.trim()),
      if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
      'status': 'in_progress',
      if (products.isNotEmpty) 'products': products,
    };

    final result = await _service.createVisit(payload);
    if (!mounted) return;
    if (!result.success || result.data == null) {
      setState(() => _submitting = false);
      _snack(result.message ?? 'Could not save visit.');
      return;
    }

    var visit = result.data!;
    if (_lat != null || _lng != null) {
      final checkIn = await _service.checkInVisit(
        visit.id,
        lat: _lat,
        lng: _lng,
      );
      if (checkIn.success && checkIn.data != null) {
        visit = checkIn.data!;
      }
    }

    String? uploadError;
    if (_photos.isNotEmpty) {
      final upload = await _service.uploadAttachments(
        attachableType: 'visit',
        attachableId: visit.id,
        employeeId: employeeId,
        photos: _photos.map((x) => File(x.path)).toList(),
      );
      if (!upload.success) {
        uploadError = upload.message ?? 'Photo upload failed.';
      }
    }

    if (!mounted) return;
    setState(() {
      _submitting = false;
      _savedVisit = visit;
    });
    if (uploadError != null) {
      _snack('Visit started, but photos failed to upload — '
          'retry from the visit detail. ($uploadError)');
    } else {
      _snack('Visit started (in progress).');
    }
  }

  Future<void> _completeCheckout() async {
    final visit = _savedVisit;
    if (visit == null) return;
    setState(() => _checkingOut = true);
    try {
      double? lat = _lat;
      double? lng = _lng;
      try {
        final snap = await MarketingLocationHelper.capture();
        if (snap != null) {
          lat = snap.latitude;
          lng = snap.longitude;
        }
      } catch (_) {}

      final result = await _service.checkOutVisit(
        visit.id,
        lat: lat,
        lng: lng,
        extra: {
          if (_findings.text.trim().isNotEmpty) 'findings': _findings.text.trim(),
          if (_feedFindings.text.trim().isNotEmpty)
            'feed_findings': _feedFindings.text.trim(),
          if (_chicksFindings.text.trim().isNotEmpty)
            'chicks_findings': _chicksFindings.text.trim(),
          if (_result.text.trim().isNotEmpty) 'result': _result.text.trim(),
          if (_nextPlan.text.trim().isNotEmpty) 'next_plan': _nextPlan.text.trim(),
          if (_nextVisitDate != null)
            'next_visit_date':
                DateFormat('yyyy-MM-dd').format(_nextVisitDate!),
          if (_orderAmount.text.trim().isNotEmpty)
            'order_amount': double.tryParse(_orderAmount.text.trim()),
          if (_collectionAmount.text.trim().isNotEmpty)
            'collection_amount':
                double.tryParse(_collectionAmount.text.trim()),
          if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
        },
      );
      if (!mounted) return;
      setState(() => _checkingOut = false);
      if (!result.success || result.data == null) {
        _snack(result.message ?? 'Check-out failed.');
        return;
      }
      _snack('Visit completed.');
      final completed = result.data!;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => VisitDetailScreen(
            visitId: completed.id,
            initial: completed,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _checkingOut = false);
        _snack('Check-out failed: $e');
      }
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  InputDecoration _decoration({String? hint, bool readOnly = false}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: readOnly
          ? AppColors.background.withValues(alpha: 0.65)
          : AppColors.background,
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

  Widget _readOnly(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label),
          Text(
            (value == null || value.trim().isEmpty) ? 'â€”' : value,
            style: GoogleFonts.poppins(fontSize: 14),
          ),
        ],
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: marketingFormDismissible(
        child: Column(
          children: [
            GradientScreenHeader(
              title: _headerTitle,
              subtitle: _headerSubtitle,
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
                          _sectionTitle('Identity'),
                          _readOnly('Dealer', widget.party!.displayName),
                          if (widget.party!.address != null)
                            _readOnly('Address', widget.party!.address),
                          if (widget.party!.phone != null)
                            _readOnly('Contact', widget.party!.phone),
                          if (_zoneName != null && _zoneName!.isNotEmpty)
                            _readOnly('Zone', _zoneName),
                          if (_locationStatus != null) ...[
                            const SizedBox(height: 8),
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
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _sectionTitle('Visit'),
                          if (_loadingMarkets)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child:
                                  Center(child: CircularProgressIndicator()),
                            )
                          else
                            SearchableSelectField<Market>(
                              label: 'Market',
                              icon: Icons.store_mall_directory_outlined,
                              options: _markets,
                              selected: _selectedMarket,
                              displayString: (m) => m.displayName,
                              searchText: (m) => m.displayName.toLowerCase(),
                              enabled: !_locked,
                              onSelected: (m) =>
                                  setState(() => _selectedMarket = m),
                            ),
                          const SizedBox(height: 14),
                          SearchableSelectField<BookingFormCompany>(
                            label: 'Company',
                            icon: Icons.apartment_outlined,
                            options: _companies,
                            selected: _selectedCompany,
                            displayString: (c) => c.displayName,
                            searchText: (c) => c.displayName.toLowerCase(),
                            enabled: !_locked,
                            onSelected: (c) =>
                                setState(() => _selectedCompany = c),
                          ),
                          const SizedBox(height: 14),
                          SearchableSelectField<BookingFormSector>(
                            label: 'Sector',
                            icon: Icons.hub_outlined,
                            options: _selectedCompany == null
                                ? _sectors
                                : _sectors
                                    .where(
                                      (s) =>
                                          s.companyId == _selectedCompany!.id,
                                    )
                                    .toList(),
                            selected: _selectedSector,
                            displayString: (s) => s.name,
                            searchText: (s) => s.searchText,
                            enabled: !_locked,
                            onSelected: (s) =>
                                setState(() => _selectedSector = s),
                          ),
                          const SizedBox(height: 14),
                          SearchableTextField(
                            label: 'Visit type',
                            controller: _visitType,
                            suggestions: kPartyVisitTypeLabels,
                            hintText: 'Type or pick visit type',
                            enabled: !_locked,
                            icon: Icons.category_outlined,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _sectionTitle('Commercial'),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    _label('Order amount'),
                                    VoiceTextField(
                                      controller: _orderAmount,
                                      keyboardType: TextInputType.number,
                                      decoration: _decoration(),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    _label('Collection amount'),
                                    VoiceTextField(
                                      controller: _collectionAmount,
                                      keyboardType: TextInputType.number,
                                      decoration: _decoration(),
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
                          _sectionTitle('Narrative'),
                          _label('Objective'),
                          VoiceTextField(
                            controller: _objective,
                            enabled: !_locked,
                            decoration: _decoration(
                              hint: 'e.g. Stock check, order, collection',
                            ),
                          ),
                          const SizedBox(height: 14),
                          _label('Findings'),
                          VoiceTextField(
                            controller: _findings,
                            maxLines: 2,
                            decoration: _decoration(),
                          ),
                          const SizedBox(height: 14),
                          _label('Feed findings'),
                          VoiceTextField(
                            controller: _feedFindings,
                            maxLines: 2,
                            decoration: _decoration(
                              hint: 'Feed stock, brands, movement…',
                            ),
                          ),
                          const SizedBox(height: 14),
                          _label('Chicks findings'),
                          VoiceTextField(
                            controller: _chicksFindings,
                            maxLines: 2,
                            decoration: _decoration(
                              hint: 'Chicks demand, hatchery sources…',
                            ),
                          ),
                          const SizedBox(height: 14),
                          _label('Result'),
                          VoiceTextField(
                            controller: _result,
                            decoration: _decoration(),
                          ),
                          const SizedBox(height: 14),
                          _label('Next plan'),
                          VoiceTextField(
                            controller: _nextPlan,
                            maxLines: 2,
                            decoration: _decoration(),
                          ),
                          const SizedBox(height: 14),
                          _label('Next visit date'),
                          InkWell(
                            onTap: _pickNextVisitDate,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _nextVisitDate == null
                                          ? 'Select date'
                                          : DateFormat('dd MMM yyyy')
                                              .format(_nextVisitDate!),
                                      style: GoogleFonts.poppins(fontSize: 13),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.calendar_today_outlined,
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _label('Notes'),
                          VoiceTextField(
                            controller: _notes,
                            maxLines: 2,
                            decoration: _decoration(),
                          ),
                          const SizedBox(height: 14),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'GPS verified',
                              style: GoogleFonts.poppins(fontSize: 13),
                            ),
                            value: _geoVerified,
                            onChanged: _locked
                                ? null
                                : (v) => setState(() => _geoVerified = v),
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
                              Expanded(
                                child: _sectionTitle('Product observations'),
                              ),
                              if (!_locked)
                                TextButton.icon(
                                  onPressed: () => setState(() {
                                    final row = VisitObsRow();
                                    row.observationType =
                                        kDealerObservationTypes.first;
                                    row.attachAmountListeners(true);
                                    _products.add(row);
                                  }),
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('Add'),
                                ),
                            ],
                          ),
                          Text(
                            identical(
                                  _catalogProducts,
                                  MarketingDemoMasters.products,
                                )
                                ? 'Products: demo catalog (Sales list empty)'
                                : 'Products: Sales form-data',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: AppColors.textHint,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...List.generate(_products.length, (i) {
                            final row = _products[i];
                            const obsTypes = kDealerObservationTypes;
                            if (!obsTypes.contains(row.observationType)) {
                              row.observationType = obsTypes.first;
                            }
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
                                      options: _catalogProducts,
                                      selected: row.product,
                                      displayString: (p) => p.displayName,
                                      searchText: (p) => p.searchText,
                                      enabled: !_locked,
                                      onSelected: (p) {
                                        setState(() {
                                          row.product = p;
                                          if (p != null) {
                                            row.name.text = p.name;
                                          }
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 8),
                                    VoiceTextField(
                                      controller: row.name,
                                      enabled: !_locked,
                                      decoration:
                                          _decoration(hint: 'Product name'),
                                    ),
                                    const SizedBox(height: 8),
                                    DropdownButtonFormField<String>(
                                      initialValue: row.observationType,
                                      decoration: _decoration(
                                        hint: 'Observation type',
                                      ),
                                      items: obsTypes
                                          .map(
                                            (t) => DropdownMenuItem(
                                              value: t,
                                              child: Text(t),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: _locked
                                          ? null
                                          : (v) {
                                              if (v != null) {
                                                setState(
                                                  () =>
                                                      row.observationType = v,
                                                );
                                              }
                                            },
                                    ),
                                    const SizedBox(height: 8),
                                    SearchableSelectField<MarketingDemoNamed>(
                                      label: 'Unit (demo)',
                                      icon: Icons.straighten,
                                      options: MarketingDemoMasters.units,
                                      selected: row.unit,
                                      displayString: (u) => u.displayName,
                                      searchText: (u) => u.searchText,
                                      enabled: !_locked,
                                      onSelected: (u) =>
                                          setState(() => row.unit = u),
                                    ),
                                    const SizedBox(height: 8),
                                    VoiceTextField(
                                      controller: row.brand,
                                      enabled: !_locked,
                                      decoration:
                                          _decoration(hint: 'Brand name'),
                                    ),
                                    const SizedBox(height: 8),
                                    VoiceTextField(
                                      controller: row.competitor,
                                      enabled: !_locked,
                                      decoration: _decoration(
                                        hint: 'Competitor company',
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: VoiceTextField(
                                            controller: row.stock,
                                            enabled: !_locked,
                                            keyboardType:
                                                TextInputType.number,
                                            decoration:
                                                _decoration(hint: 'Stock'),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: VoiceTextField(
                                            controller: row.demand,
                                            enabled: !_locked,
                                            keyboardType:
                                                TextInputType.number,
                                            decoration:
                                                _decoration(hint: 'Demand'),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: VoiceTextField(
                                            controller: row.order,
                                            enabled: !_locked,
                                            keyboardType:
                                                TextInputType.number,
                                            decoration: _decoration(
                                              hint: 'Order qty',
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: VoiceTextField(
                                            controller: row.price,
                                            enabled: !_locked,
                                            keyboardType:
                                                TextInputType.number,
                                            decoration: _decoration(
                                              hint: 'Unit price',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: row.amount,
                                      readOnly: true,
                                      keyboardType: TextInputType.number,
                                      decoration: _decoration(
                                        hint: 'Amount',
                                        readOnly: true,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    VoiceTextField(
                                      controller: row.notes,
                                      enabled: !_locked,
                                      decoration:
                                          _decoration(hint: 'Line notes'),
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
                          _sectionTitle('Photos *'),
                          if (!_locked)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                'At least one photo is required to start the visit.',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: AppColors.textHint,
                                ),
                              ),
                            ),
                          if (!_locked)
                            MarketingPhotoPicker(
                              photos: _photos,
                              onPick: _pickPhotos,
                              onRemove: (i) =>
                                  setState(() => _photos.removeAt(i)),
                            )
                          else if (_photos.isNotEmpty)
                            Text(
                              '${_photos.length} photo(s) uploaded',
                              style: GoogleFonts.poppins(fontSize: 13),
                            ),
                          const SizedBox(height: 24),
                          if (!_locked)
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
                                        'Start visit',
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                            )
                          else
                            SizedBox(
                              height: 50,
                              child: ElevatedButton(
                                onPressed:
                                    _checkingOut ? null : _completeCheckout,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: _checkingOut
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        'Complete / check-out',
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
      ),
    );
  }
}

