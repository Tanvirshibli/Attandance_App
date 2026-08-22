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
import '../../widgets/searchable_select_field.dart';
import '../../widgets/section_card.dart';

class FarmSurveyFormScreen extends StatefulWidget {
  const FarmSurveyFormScreen({super.key, required this.party, this.visitId});

  final Party party;
  final int? visitId;

  @override
  State<FarmSurveyFormScreen> createState() => _FarmSurveyFormScreenState();
}

class _FarmSurveyFormScreenState extends State<FarmSurveyFormScreen> {
  final MarketingService _service = MarketingService();
  final AuthService _authService = AuthService();
  final SalesService _salesService = SalesService();

  DateTime _surveyDate = DateTime.now();
  DateTime? _hatchDate;
  DateTime? _receivingDate;
  TimeOfDay? _receivingTime;

  final _quantity = TextEditingController();
  final _ageDays = TextEditingController();
  final _totalMortality = TextEditingController();
  final _presentMortality = TextEditingController();
  final _mortalityPct = TextEditingController();
  final _restOfBirds = TextEditingController();
  final _totalFeed = TextEditingController();
  final _avgFeed = TextEditingController();
  final _productionPercent = TextEditingController();
  final _fcr = TextEditingController();
  final _totalBodyWeight = TextEditingController();
  final _avgBodyWeight = TextEditingController();
  final _bagWeight = TextEditingController();
  final _feederQty = TextEditingController();
  final _drinkerQty = TextEditingController();
  final _avgTemp = TextEditingController();
  final _space = TextEditingController();
  final _uniformity = TextEditingController();
  final _diseaseDetails = TextEditingController();
  final _problems = TextEditingController();
  final _remarks = TextEditingController();
  final _comments = TextEditingController();

  int _biosecurity = 3;
  int _management = 3;
  int _technical = 3;
  int _economic = 3;
  bool _diseasePresent = false;
  bool _submitting = false;
  bool _computing = false;
  String _officerName = '';
  List<Party> _dealers = const [];
  Party? _dealer;
  List<BookingFormCompany> _companies = const [];
  MarketingDemoNamed? _breed;
  MarketingDemoNamed? _docCompany;
  MarketingDemoNamed? _feedCompany;
  MarketingDemoNamed? _shedDesign;
  MarketingDemoNamed? _curtain;
  MarketingDemoNamed? _floor;
  MarketingDemoNamed? _territory;
  MarketingDemoNamed? _zone;
  BookingFormCompany? _liveDocCompany;
  BookingFormCompany? _liveFeedCompany;
  double? _lat;
  double? _lng;
  bool _geoVerified = false;
  final List<XFile> _photos = [];

  @override
  void initState() {
    super.initState();
    _quantity.addListener(_recompute);
    _totalMortality.addListener(_recompute);
    _loadContext();
    _autoFillLocation();
  }

  @override
  void dispose() {
    _quantity.dispose();
    _ageDays.dispose();
    _totalMortality.dispose();
    _presentMortality.dispose();
    _mortalityPct.dispose();
    _restOfBirds.dispose();
    _totalFeed.dispose();
    _avgFeed.dispose();
    _productionPercent.dispose();
    _fcr.dispose();
    _totalBodyWeight.dispose();
    _avgBodyWeight.dispose();
    _bagWeight.dispose();
    _feederQty.dispose();
    _drinkerQty.dispose();
    _avgTemp.dispose();
    _space.dispose();
    _uniformity.dispose();
    _diseaseDetails.dispose();
    _problems.dispose();
    _remarks.dispose();
    _comments.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    final profile = await _authService.getCurrentUserProfile();
    final dealers = await _service.listParties(
      employeeId: profile?.canonicalEmployeeId,
      partyType: 'dealer',
    );
    final formData = await _salesService.fetchBookingFormData();
    if (!mounted) return;
    setState(() {
      _officerName = profile?.name ?? '';
      _dealers = dealers.data ?? const [];
      if (formData.success && formData.data != null) {
        _companies = formData.data!.companies.where((c) => c.id > 0).toList();
      }
      _dealer = MarketingDemoMasters.byId(
        _dealers,
        widget.party.parentPartyId,
        (p) => p.id,
      );
    });
  }

  Future<void> _autoFillLocation() async {
    try {
      final snap = await MarketingLocationHelper.capture();
      if (!mounted || snap == null) return;
      setState(() {
        _lat = snap.latitude;
        _lng = snap.longitude;
        _geoVerified = true;
      });
    } catch (_) {}
  }

  void _recompute() {
    if (_computing) return;
    final qty = double.tryParse(_quantity.text.trim());
    final mort = double.tryParse(_totalMortality.text.trim());
    if (qty == null || qty <= 0 || mort == null) return;
    final rest = (qty - mort).clamp(0, qty);
    final pct = (mort / qty) * 100;
    _computing = true;
    _restOfBirds.text = rest.toStringAsFixed(0);
    _mortalityPct.text = pct.toStringAsFixed(2);
    _computing = false;
  }

  Future<void> _pickDate({
    required DateTime? current,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _pickReceivingTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _receivingTime ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _receivingTime = picked);
  }

  Future<void> _pickPhotos() async {
    final files = await ImagePicker().pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return;
    setState(() => _photos.addAll(files));
  }

  Future<void> _submit() async {
    final profile = await _authService.getCurrentUserProfile();
    final employeeId = profile?.canonicalEmployeeId;
    if (employeeId == null || employeeId <= 0) {
      _snack('Employee profile not linked.');
      return;
    }
    setState(() => _submitting = true);
    final payload = <String, dynamic>{
      'party_id': widget.party.id,
      'employee_id': employeeId,
      if (widget.visitId != null) 'visit_id': widget.visitId,
      if (_dealer != null) 'dealer_party_id': _dealer!.id,
      'survey_date': DateFormat('yyyy-MM-dd').format(_surveyDate),
      'survey_type': 'poultry',
      if (_hatchDate != null)
        'hatch_date': DateFormat('yyyy-MM-dd').format(_hatchDate!),
      if (_receivingDate != null)
        'receiving_date': DateFormat('yyyy-MM-dd').format(_receivingDate!),
      if (_receivingTime != null)
        'receiving_time':
            '${_receivingTime!.hour.toString().padLeft(2, '0')}:${_receivingTime!.minute.toString().padLeft(2, '0')}',
      if (_breed != null) 'breed': _breed!.name,
      'doc_company': _liveDocCompany?.displayName ?? _docCompany?.name,
      'feed_company': _liveFeedCompany?.displayName ?? _feedCompany?.name,
      if (widget.party.businessYears != null)
        'farming_years': widget.party.businessYears,
      if (_quantity.text.trim().isNotEmpty)
        'quantity': double.tryParse(_quantity.text.trim()),
      if (_ageDays.text.trim().isNotEmpty)
        'age_days': int.tryParse(_ageDays.text.trim()),
      if (_totalMortality.text.trim().isNotEmpty)
        'total_mortality': double.tryParse(_totalMortality.text.trim()),
      if (_presentMortality.text.trim().isNotEmpty)
        'present_mortality': double.tryParse(_presentMortality.text.trim()),
      if (_mortalityPct.text.trim().isNotEmpty)
        'mortality_percent': double.tryParse(_mortalityPct.text.trim()),
      if (_restOfBirds.text.trim().isNotEmpty)
        'rest_of_birds': double.tryParse(_restOfBirds.text.trim()),
      if (_restOfBirds.text.trim().isNotEmpty)
        'current_birds': double.tryParse(_restOfBirds.text.trim()),
      if (_totalFeed.text.trim().isNotEmpty)
        'total_feed_intake_kg': double.tryParse(_totalFeed.text.trim()),
      if (_avgFeed.text.trim().isNotEmpty)
        'avg_feed_intake_kg': double.tryParse(_avgFeed.text.trim()),
      if (_productionPercent.text.trim().isNotEmpty)
        'production_percent': double.tryParse(_productionPercent.text.trim()),
      if (_fcr.text.trim().isNotEmpty) 'fcr': double.tryParse(_fcr.text.trim()),
      if (_totalBodyWeight.text.trim().isNotEmpty)
        'total_body_weight_kg': double.tryParse(_totalBodyWeight.text.trim()),
      if (_avgBodyWeight.text.trim().isNotEmpty)
        'avg_body_weight_kg': double.tryParse(_avgBodyWeight.text.trim()),
      if (_bagWeight.text.trim().isNotEmpty)
        'bag_weight_kg': double.tryParse(_bagWeight.text.trim()),
      if (_shedDesign != null) 'shed_design': _shedDesign!.name,
      if (_shedDesign != null) 'housing_type': _shedDesign!.name,
      if (_curtain != null) 'curtain_type': _curtain!.name,
      if (_floor != null) 'floor_type': _floor!.name,
      if (_feederQty.text.trim().isNotEmpty)
        'feeder_qty': double.tryParse(_feederQty.text.trim()),
      if (_drinkerQty.text.trim().isNotEmpty)
        'drinker_qty': double.tryParse(_drinkerQty.text.trim()),
      if (_avgTemp.text.trim().isNotEmpty)
        'avg_temperature': double.tryParse(_avgTemp.text.trim()),
      if (_space.text.trim().isNotEmpty) 'space_note': _space.text.trim(),
      if (_uniformity.text.trim().isNotEmpty)
        'uniformity_percent': double.tryParse(_uniformity.text.trim()),
      'biosecurity_rating': _biosecurity,
      'management_rating': _management,
      'technical_support_rating': _technical,
      'economic_solvency_rating': _economic,
      'disease_present': _diseasePresent,
      if (_diseasePresent && _diseaseDetails.text.trim().isNotEmpty)
        'disease_details': _diseaseDetails.text.trim(),
      if (_problems.text.trim().isNotEmpty) 'problems': _problems.text.trim(),
      if (_remarks.text.trim().isNotEmpty) 'notes': _remarks.text.trim(),
      if (_comments.text.trim().isNotEmpty) 'comments': _comments.text.trim(),
      if (_territory != null) 'territory': _territory!.name,
      if (_zone != null) 'zone': _zone!.name,
      if (_lat != null) 'check_in_lat': _lat,
      if (_lng != null) 'check_in_lng': _lng,
      'geo_verified': _geoVerified,
      'status': 'submitted',
    };
    payload.removeWhere((key, value) => value == null || value == '');

    final result = await _service.createFarmSurvey(payload);
    if (!mounted) return;
    if (!result.success || result.data == null) {
      setState(() => _submitting = false);
      _snack(result.message ?? 'Could not save farm visit report.');
      return;
    }

    final survey = result.data!;
    if (_photos.isNotEmpty) {
      await _service.uploadAttachments(
        attachableType: 'survey',
        attachableId: survey.id,
        employeeId: employeeId,
        photos: _photos.map((x) => File(x.path)).toList(),
      );
    }
    if (!mounted) return;
    setState(() => _submitting = false);
    _snack('Farm visit report saved.');
    Navigator.of(context).pop(survey);
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

  Widget _readOnly(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label),
          Text(
            (value == null || value.trim().isEmpty) ? '—' : value,
            style: GoogleFonts.poppins(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _dateTile(String label, DateTime? value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          value == null ? label : DateFormat('dd MMM yyyy').format(value),
          style: GoogleFonts.poppins(fontSize: 13),
        ),
      ),
    );
  }

  Widget _ratingRow(String label, int value, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: GoogleFonts.poppins(fontSize: 13)),
          ),
          for (var i = 1; i <= 5; i++)
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => onChanged(i),
              icon: Icon(
                i <= value ? Icons.star : Icons.star_border,
                color: AppColors.warning,
                size: 22,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final farm = widget.party;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          GradientScreenHeader(
            title: 'Farm visit report',
            subtitle: farm.displayName,
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
                        _label('Date'),
                        _dateTile(
                          'Select date',
                          _surveyDate,
                          () => _pickDate(
                            current: _surveyDate,
                            onPicked: (d) => setState(() => _surveyDate = d),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _readOnly('Name of farm', farm.displayName),
                        _readOnly(
                          'Name of owner',
                          farm.ownerName ?? farm.contactPerson,
                        ),
                        _readOnly('Address', farm.address),
                        _readOnly('Contact No.', farm.phone),
                        _readOnly(
                          'Farming years',
                          farm.businessYears?.toString(),
                        ),
                        SearchableSelectField<Party>(
                          label: 'Name of dealer',
                          icon: Icons.storefront_outlined,
                          options: _dealers,
                          selected: _dealer,
                          displayString: (d) => d.displayName,
                          searchText: (d) =>
                              '${d.displayName} ${d.phone ?? ''} ${d.address ?? ''}'
                                  .toLowerCase(),
                          onSelected: (d) => setState(() => _dealer = d),
                        ),
                        const SizedBox(height: 12),
                        _readOnly(
                          'Dealer address',
                          _dealer?.address ?? farm.parentPartyAddress,
                        ),
                        _readOnly(
                          'Dealer contact',
                          _dealer?.phone ?? farm.parentPartyPhone,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _label('Hatch date'),
                        _dateTile(
                          'Select hatch date',
                          _hatchDate,
                          () => _pickDate(
                            current: _hatchDate,
                            onPicked: (d) => setState(() => _hatchDate = d),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _label('Receiving date'),
                        _dateTile(
                          'Select receiving date',
                          _receivingDate,
                          () => _pickDate(
                            current: _receivingDate,
                            onPicked: (d) =>
                                setState(() => _receivingDate = d),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _label('Receiving time'),
                        InkWell(
                          onTap: _pickReceivingTime,
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
                            child: Text(
                              _receivingTime == null
                                  ? 'Select time'
                                  : _receivingTime!.format(context),
                              style: GoogleFonts.poppins(fontSize: 13),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SearchableSelectField<MarketingDemoNamed>(
                          label: 'Breed',
                          icon: Icons.pets_outlined,
                          options: MarketingDemoMasters.breeds,
                          selected: _breed,
                          displayString: (b) => b.displayName,
                          searchText: (b) => b.searchText,
                          onSelected: (b) => setState(() => _breed = b),
                        ),
                        const SizedBox(height: 12),
                        if (_companies.isNotEmpty)
                          SearchableSelectField<BookingFormCompany>(
                            label: 'DOC company',
                            icon: Icons.apartment_outlined,
                            options: _companies,
                            selected: _liveDocCompany,
                            displayString: (c) => c.displayName,
                            searchText: (c) => c.displayName.toLowerCase(),
                            onSelected: (c) =>
                                setState(() => _liveDocCompany = c),
                          )
                        else
                          SearchableSelectField<MarketingDemoNamed>(
                            label: 'DOC company',
                            icon: Icons.apartment_outlined,
                            options: MarketingDemoMasters.docCompanies,
                            selected: _docCompany,
                            displayString: (c) => c.displayName,
                            searchText: (c) => c.searchText,
                            onSelected: (c) =>
                                setState(() => _docCompany = c),
                          ),
                        const SizedBox(height: 12),
                        if (_companies.isNotEmpty)
                          SearchableSelectField<BookingFormCompany>(
                            label: 'Feed company',
                            icon: Icons.inventory_2_outlined,
                            options: _companies,
                            selected: _liveFeedCompany,
                            displayString: (c) => c.displayName,
                            searchText: (c) => c.displayName.toLowerCase(),
                            onSelected: (c) =>
                                setState(() => _liveFeedCompany = c),
                          )
                        else
                          SearchableSelectField<MarketingDemoNamed>(
                            label: 'Feed company',
                            icon: Icons.inventory_2_outlined,
                            options: MarketingDemoMasters.feedCompanies,
                            selected: _feedCompany,
                            displayString: (c) => c.displayName,
                            searchText: (c) => c.searchText,
                            onSelected: (c) =>
                                setState(() => _feedCompany = c),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _label('Quantity'),
                        TextField(
                          controller: _quantity,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Age'),
                        TextField(
                          controller: _ageDays,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(hint: 'Days'),
                        ),
                        const SizedBox(height: 12),
                        _label('Total mortality'),
                        TextField(
                          controller: _totalMortality,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Present mortality'),
                        TextField(
                          controller: _presentMortality,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Mortality %'),
                        TextField(
                          controller: _mortalityPct,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Rest of bird'),
                        TextField(
                          controller: _restOfBirds,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Total feed intake'),
                        TextField(
                          controller: _totalFeed,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(hint: 'kg'),
                        ),
                        const SizedBox(height: 12),
                        _label('Av. feed intake'),
                        TextField(
                          controller: _avgFeed,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(hint: 'kg'),
                        ),
                        const SizedBox(height: 12),
                        _label('Production %'),
                        TextField(
                          controller: _productionPercent,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('FCR'),
                        TextField(
                          controller: _fcr,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Total body weight (kg)'),
                        TextField(
                          controller: _totalBodyWeight,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Av. B/W'),
                        TextField(
                          controller: _avgBodyWeight,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Per bag weight (kg)'),
                        TextField(
                          controller: _bagWeight,
                          keyboardType: TextInputType.number,
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
                        SearchableSelectField<MarketingDemoNamed>(
                          label: 'Shed design',
                          icon: Icons.home_work_outlined,
                          options: MarketingDemoMasters.shedDesigns,
                          selected: _shedDesign,
                          displayString: (s) => s.displayName,
                          searchText: (s) => s.searchText,
                          onSelected: (s) => setState(() => _shedDesign = s),
                        ),
                        const SizedBox(height: 12),
                        SearchableSelectField<MarketingDemoNamed>(
                          label: 'Curtain',
                          icon: Icons.blinds_outlined,
                          options: MarketingDemoMasters.curtains,
                          selected: _curtain,
                          displayString: (s) => s.displayName,
                          searchText: (s) => s.searchText,
                          onSelected: (s) => setState(() => _curtain = s),
                        ),
                        const SizedBox(height: 12),
                        SearchableSelectField<MarketingDemoNamed>(
                          label: 'Floor',
                          icon: Icons.layers_outlined,
                          options: MarketingDemoMasters.floors,
                          selected: _floor,
                          displayString: (s) => s.displayName,
                          searchText: (s) => s.searchText,
                          onSelected: (s) => setState(() => _floor = s),
                        ),
                        const SizedBox(height: 12),
                        _label('Quantity of feeder'),
                        TextField(
                          controller: _feederQty,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Quantity drinker'),
                        TextField(
                          controller: _drinkerQty,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Av. temperature'),
                        TextField(
                          controller: _avgTemp,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Space'),
                        TextField(
                          controller: _space,
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
                        _ratingRow(
                          'Biosecurity',
                          _biosecurity,
                          (v) => setState(() => _biosecurity = v),
                        ),
                        _label('Uniformity'),
                        TextField(
                          controller: _uniformity,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(hint: '%'),
                        ),
                        const SizedBox(height: 8),
                        _ratingRow(
                          'Management',
                          _management,
                          (v) => setState(() => _management = v),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Diseases',
                            style: GoogleFonts.poppins(fontSize: 13),
                          ),
                          value: _diseasePresent,
                          onChanged: (v) =>
                              setState(() => _diseasePresent = v),
                        ),
                        if (_diseasePresent) ...[
                          TextField(
                            controller: _diseaseDetails,
                            maxLines: 2,
                            decoration: _decoration(hint: 'Disease details'),
                          ),
                          const SizedBox(height: 8),
                        ],
                        _ratingRow(
                          'Technical support',
                          _technical,
                          (v) => setState(() => _technical = v),
                        ),
                        _label('Problem facing'),
                        TextField(
                          controller: _problems,
                          maxLines: 2,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 8),
                        _ratingRow(
                          'Economical solvency',
                          _economic,
                          (v) => setState(() => _economic = v),
                        ),
                        _label('Remarks'),
                        TextField(
                          controller: _remarks,
                          maxLines: 2,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Comments'),
                        TextField(
                          controller: _comments,
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
                        _readOnly('Reporting officer', _officerName),
                        SearchableSelectField<MarketingDemoNamed>(
                          label: 'Territory',
                          icon: Icons.map_outlined,
                          options: MarketingDemoMasters.territories,
                          selected: _territory,
                          displayString: (t) => t.displayName,
                          searchText: (t) => t.searchText,
                          onSelected: (t) => setState(() => _territory = t),
                        ),
                        const SizedBox(height: 12),
                        SearchableSelectField<MarketingDemoNamed>(
                          label: 'Zone',
                          icon: Icons.public,
                          options: MarketingDemoMasters.zones,
                          selected: _zone,
                          displayString: (z) => z.displayName,
                          searchText: (z) => z.searchText,
                          onSelected: (z) => setState(() => _zone = z),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _pickPhotos,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(
                            _photos.isEmpty
                                ? 'Add photos'
                                : '${_photos.length} photo(s)',
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _submitting ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
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
                                    'Submit report',
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
