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
import '../../utils/marketing_location_helper.dart';
import '../../widgets/gradient_screen_header.dart';
import '../../widgets/searchable_text_field.dart';
import '../../widgets/section_card.dart';

class FarmSurveyFormScreen extends StatefulWidget {
  const FarmSurveyFormScreen({super.key, required this.party});

  final Party party;

  @override
  State<FarmSurveyFormScreen> createState() => _FarmSurveyFormScreenState();
}

class _FarmSurveyFormScreenState extends State<FarmSurveyFormScreen> {
  final MarketingService _service = MarketingService();
  final AuthService _authService = AuthService();

  DateTime _surveyDate = DateTime.now();
  DateTime? _hatchDate;
  DateTime? _receivingDate;
  TimeOfDay? _receivingTime;

  final _visitType = TextEditingController(text: 'Regular farm visit');
  final _breed = TextEditingController();
  final _docCompany = TextEditingController();
  final _feedCompany = TextEditingController();
  final _shedDesign = TextEditingController();
  final _curtain = TextEditingController();
  final _floor = TextEditingController();
  final _territory = TextEditingController();
  final _zone = TextEditingController();
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
  String _officerDesignation = '';
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
    _visitType.dispose();
    _breed.dispose();
    _docCompany.dispose();
    _feedCompany.dispose();
    _shedDesign.dispose();
    _curtain.dispose();
    _floor.dispose();
    _territory.dispose();
    _zone.dispose();
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
    if (!mounted) return;
    setState(() {
      _officerName = profile?.name ?? '';
      _officerDesignation = profile?.designation ?? '';
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

  String? _textValue(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
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

    final extraData = <String, dynamic>{
      if (_textValue(_visitType) != null)
        'visit_type_label': _textValue(_visitType),
      if (_textValue(_avgTemp) != null)
        'avg_temperature_note': _textValue(_avgTemp),
      if (_officerDesignation.isNotEmpty)
        'reporting_officer_designation': _officerDesignation,
    };

    final farm = widget.party;
    final payload = <String, dynamic>{
      'party_id': farm.id,
      'employee_id': employeeId,
      if (farm.parentPartyId != null) 'dealer_party_id': farm.parentPartyId,
      'survey_date': DateFormat('yyyy-MM-dd').format(_surveyDate),
      'survey_type': 'poultry',
      if (_hatchDate != null)
        'hatch_date': DateFormat('yyyy-MM-dd').format(_hatchDate!),
      if (_receivingDate != null)
        'receiving_date': DateFormat('yyyy-MM-dd').format(_receivingDate!),
      if (_receivingTime != null)
        'receiving_time':
            '${_receivingTime!.hour.toString().padLeft(2, '0')}:${_receivingTime!.minute.toString().padLeft(2, '0')}',
      if (_textValue(_breed) != null) 'breed': _textValue(_breed),
      if (_textValue(_docCompany) != null)
        'doc_company': _textValue(_docCompany),
      if (_textValue(_feedCompany) != null)
        'feed_company': _textValue(_feedCompany),
      if (farm.businessYears != null) 'farming_years': farm.businessYears,
      if (_textValue(_quantity) != null)
        'quantity': double.tryParse(_quantity.text.trim()),
      if (_textValue(_ageDays) != null)
        'age_days': int.tryParse(_ageDays.text.trim()),
      if (_textValue(_totalMortality) != null)
        'total_mortality': double.tryParse(_totalMortality.text.trim()),
      if (_textValue(_presentMortality) != null)
        'present_mortality': double.tryParse(_presentMortality.text.trim()),
      if (_textValue(_mortalityPct) != null)
        'mortality_percent': double.tryParse(_mortalityPct.text.trim()),
      if (_textValue(_restOfBirds) != null)
        'rest_of_birds': double.tryParse(_restOfBirds.text.trim()),
      if (_textValue(_restOfBirds) != null)
        'current_birds': double.tryParse(_restOfBirds.text.trim()),
      if (_textValue(_totalFeed) != null)
        'total_feed_intake_kg': double.tryParse(_totalFeed.text.trim()),
      if (_textValue(_avgFeed) != null)
        'avg_feed_intake_kg': double.tryParse(_avgFeed.text.trim()),
      if (_textValue(_productionPercent) != null)
        'production_percent': double.tryParse(_productionPercent.text.trim()),
      if (_textValue(_fcr) != null) 'fcr': double.tryParse(_fcr.text.trim()),
      if (_textValue(_totalBodyWeight) != null)
        'total_body_weight_kg': double.tryParse(_totalBodyWeight.text.trim()),
      if (_textValue(_avgBodyWeight) != null)
        'avg_body_weight_kg': double.tryParse(_avgBodyWeight.text.trim()),
      if (_textValue(_bagWeight) != null)
        'bag_weight_kg': double.tryParse(_bagWeight.text.trim()),
      if (_textValue(_shedDesign) != null) 'shed_design': _textValue(_shedDesign),
      if (_textValue(_shedDesign) != null)
        'housing_type': _textValue(_shedDesign),
      if (_textValue(_curtain) != null) 'curtain_type': _textValue(_curtain),
      if (_textValue(_floor) != null) 'floor_type': _textValue(_floor),
      if (_textValue(_feederQty) != null)
        'feeder_qty': double.tryParse(_feederQty.text.trim()),
      if (_textValue(_drinkerQty) != null)
        'drinker_qty': double.tryParse(_drinkerQty.text.trim()),
      if (_textValue(_space) != null) 'space_note': _textValue(_space),
      if (_textValue(_uniformity) != null)
        'uniformity_percent': double.tryParse(_uniformity.text.trim()),
      'biosecurity_rating': _biosecurity,
      'management_rating': _management,
      'technical_support_rating': _technical,
      'economic_solvency_rating': _economic,
      'disease_present': _diseasePresent,
      if (_diseasePresent && _textValue(_diseaseDetails) != null)
        'disease_details': _textValue(_diseaseDetails),
      if (_textValue(_problems) != null) 'problems': _textValue(_problems),
      if (_textValue(_remarks) != null) 'notes': _textValue(_remarks),
      if (_textValue(_comments) != null) 'comments': _textValue(_comments),
      if (_textValue(_territory) != null) 'territory': _textValue(_territory),
      if (_textValue(_zone) != null) 'zone': _textValue(_zone),
      if (extraData.isNotEmpty) 'extra_data': extraData,
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

  Widget _suggestField({
    required String label,
    required TextEditingController controller,
    required List<String> suggestions,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return SearchableTextField(
      label: label,
      controller: controller,
      suggestions: suggestions,
      hintText: hint ?? 'Type or pick…',
      keyboardType: keyboardType,
    );
  }

  List<String> _namedSuggestions(List<MarketingDemoNamed> items) =>
      items.map((e) => e.name).toList();

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
                        _suggestField(
                          label: 'Visit type',
                          controller: _visitType,
                          suggestions: MarketingDemoMasters.visitTypes,
                        ),
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
                          farm.businessYears?.toStringAsFixed(0),
                        ),
                        _readOnly('Name of dealer', farm.parentPartyName),
                        _readOnly('Dealer address', farm.parentPartyAddress),
                        _readOnly('Dealer contact', farm.parentPartyPhone),
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
                        _suggestField(
                          label: 'Breed',
                          controller: _breed,
                          suggestions: _namedSuggestions(
                            MarketingDemoMasters.breeds,
                          ),
                        ),
                        _suggestField(
                          label: 'DOC company',
                          controller: _docCompany,
                          suggestions: _namedSuggestions(
                            MarketingDemoMasters.docCompanies,
                          ),
                        ),
                        _suggestField(
                          label: 'Feed company',
                          controller: _feedCompany,
                          suggestions: _namedSuggestions(
                            MarketingDemoMasters.feedCompanies,
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
                        _label('Quantity'),
                        TextField(
                          controller: _quantity,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(hint: 'Pcs'),
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
                          decoration: _decoration(hint: 'Pcs'),
                        ),
                        const SizedBox(height: 12),
                        _label('Present mortality'),
                        TextField(
                          controller: _presentMortality,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(hint: 'Pcs'),
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
                          decoration: _decoration(hint: 'Pcs'),
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
                          decoration: _decoration(hint: 'grams per bird'),
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
                          decoration: _decoration(hint: 'grams'),
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
                        _suggestField(
                          label: 'Shed design',
                          controller: _shedDesign,
                          suggestions: _namedSuggestions(
                            MarketingDemoMasters.shedDesigns,
                          ),
                        ),
                        _suggestField(
                          label: 'Curtain',
                          controller: _curtain,
                          suggestions: _namedSuggestions(
                            MarketingDemoMasters.curtains,
                          ),
                        ),
                        _suggestField(
                          label: 'Floor',
                          controller: _floor,
                          suggestions: _namedSuggestions(
                            MarketingDemoMasters.floors,
                          ),
                        ),
                        _label('Quantity of feeder'),
                        TextField(
                          controller: _feederQty,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(hint: 'Pcs'),
                        ),
                        const SizedBox(height: 12),
                        _label('Quantity drinker'),
                        TextField(
                          controller: _drinkerQty,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(hint: 'Pcs'),
                        ),
                        const SizedBox(height: 12),
                        _label('Av. temperature'),
                        TextField(
                          controller: _avgTemp,
                          decoration: _decoration(hint: 'e.g. 28-30'),
                        ),
                        const SizedBox(height: 12),
                        _label('Space'),
                        TextField(
                          controller: _space,
                          decoration: _decoration(hint: 'sq ft'),
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
                          decoration: _decoration(hint: '% or note'),
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
                        _readOnly('Designation', _officerDesignation),
                        _suggestField(
                          label: 'Territory',
                          controller: _territory,
                          suggestions: _namedSuggestions(
                            MarketingDemoMasters.territories,
                          ),
                        ),
                        _suggestField(
                          label: 'Zone',
                          controller: _zone,
                          suggestions: _namedSuggestions(
                            MarketingDemoMasters.zones,
                          ),
                        ),
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
