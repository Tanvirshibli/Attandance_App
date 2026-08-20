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
  final _farmType = TextEditingController();
  final _birdCapacity = TextEditingController();
  final _currentBirds = TextEditingController();
  final _housing = TextEditingController();
  final _feedBrand = TextEditingController();
  final _notes = TextEditingController();
  final _ageDays = TextEditingController();
  final _quantity = TextEditingController();
  final _mortality = TextEditingController();
  final _chicksBrand = TextEditingController();
  final _totalFeed = TextEditingController();
  final _avgFeed = TextEditingController();
  final _fcr = TextEditingController();
  final _bodyWeight = TextEditingController();
  final _uniformity = TextEditingController();
  final _diseaseDetails = TextEditingController();
  final _problems = TextEditingController();
  final _recommendation = TextEditingController();
  final _productionPercent = TextEditingController();
  final _landArea = TextEditingController();
  final _fertilizerKg = TextEditingController();
  final _dailyEggs = TextEditingController();
  final _crackedEgg = TextEditingController();
  final _pondArea = TextEditingController();
  final _flockAge = TextEditingController();
  final _mortalityPct = TextEditingController();
  final _feedBags = TextEditingController();

  int _biosecurity = 3;
  int _management = 3;
  int _technical = 3;
  int _economic = 3;
  bool _diseasePresent = false;
  bool _submitting = false;
  String _surveyType = 'poultry';
  MarketingDemoNamed? _quantityUnit;
  MarketingDemoProduct? _chicksProduct;
  MarketingDemoProduct? _feedProduct;
  final List<XFile> _photos = [];

  static const _surveyTypes = [
    'poultry',
    'fertilizer',
    'egg',
    'fish',
    'other',
  ];

  @override
  void dispose() {
    _farmType.dispose();
    _birdCapacity.dispose();
    _currentBirds.dispose();
    _housing.dispose();
    _feedBrand.dispose();
    _notes.dispose();
    _ageDays.dispose();
    _quantity.dispose();
    _mortality.dispose();
    _chicksBrand.dispose();
    _totalFeed.dispose();
    _avgFeed.dispose();
    _fcr.dispose();
    _bodyWeight.dispose();
    _uniformity.dispose();
    _diseaseDetails.dispose();
    _problems.dispose();
    _recommendation.dispose();
    _productionPercent.dispose();
    _landArea.dispose();
    _fertilizerKg.dispose();
    _dailyEggs.dispose();
    _crackedEgg.dispose();
    _pondArea.dispose();
    _flockAge.dispose();
    _mortalityPct.dispose();
    _feedBags.dispose();
    super.dispose();
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

    final metrics = <Map<String, dynamic>>[];
    void addMetric(
      String key,
      String label,
      TextEditingController c, {
      String? unit,
    }) {
      final raw = c.text.trim();
      if (raw.isEmpty) return;
      final numVal = double.tryParse(raw);
      metrics.add({
        'metric_key': key,
        'metric_code': key,
        'metric_label': label,
        if (numVal != null) 'value_number': numVal else 'value_text': raw,
        'unit': ?unit,
      });
    }

    addMetric('flock_age_days', 'Flock age', _flockAge, unit: 'days');
    addMetric('mortality_pct', 'Mortality', _mortalityPct, unit: '%');
    addMetric('feed_bag_stock', 'Feed bag stock', _feedBags, unit: 'bags');
    addMetric('LAND_AREA_ACRE', 'Cultivated land', _landArea, unit: 'acre');
    addMetric(
      'MONTHLY_FERTILIZER_KG',
      'Monthly fertilizer',
      _fertilizerKg,
      unit: 'kg',
    );
    addMetric('DAILY_EGG_PRODUCTION', 'Daily egg production', _dailyEggs);
    addMetric('CRACKED_EGG_PERCENT', 'Cracked egg', _crackedEgg, unit: '%');
    addMetric('POND_AREA_DECIMAL', 'Pond area', _pondArea, unit: 'decimal');

    final payload = <String, dynamic>{
      'party_id': widget.party.id,
      'employee_id': employeeId,
      if (widget.visitId != null) 'visit_id': widget.visitId,
      'survey_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'survey_type': _surveyType,
      if (_farmType.text.trim().isNotEmpty) 'farm_type': _farmType.text.trim(),
      if (_ageDays.text.trim().isNotEmpty)
        'age_days': int.tryParse(_ageDays.text.trim()),
      if (_quantity.text.trim().isNotEmpty)
        'quantity': double.tryParse(_quantity.text.trim()),
      if (_quantityUnit != null) 'quantity_unit_id': _quantityUnit!.id,
      if (_chicksProduct != null) 'chicks_product_id': _chicksProduct!.id,
      if (_feedProduct != null) 'feed_product_id': _feedProduct!.id,
      if (_mortality.text.trim().isNotEmpty)
        'mortality_quantity': double.tryParse(_mortality.text.trim()),
      if (_chicksBrand.text.trim().isNotEmpty)
        'chicks_brand': _chicksBrand.text.trim(),
      if (_birdCapacity.text.trim().isNotEmpty)
        'bird_capacity': double.tryParse(_birdCapacity.text.trim()),
      if (_currentBirds.text.trim().isNotEmpty)
        'current_birds': double.tryParse(_currentBirds.text.trim()),
      if (_housing.text.trim().isNotEmpty)
        'housing_type': _housing.text.trim(),
      if (_feedBrand.text.trim().isNotEmpty)
        'feed_brand': _feedBrand.text.trim(),
      if (_totalFeed.text.trim().isNotEmpty)
        'total_feed_intake_kg': double.tryParse(_totalFeed.text.trim()),
      if (_avgFeed.text.trim().isNotEmpty)
        'avg_feed_intake_kg': double.tryParse(_avgFeed.text.trim()),
      if (_fcr.text.trim().isNotEmpty) 'fcr': double.tryParse(_fcr.text.trim()),
      if (_bodyWeight.text.trim().isNotEmpty)
        'avg_body_weight_kg': double.tryParse(_bodyWeight.text.trim()),
      if (_uniformity.text.trim().isNotEmpty)
        'uniformity_percent': double.tryParse(_uniformity.text.trim()),
      if (_productionPercent.text.trim().isNotEmpty)
        'production_percent':
            double.tryParse(_productionPercent.text.trim()),
      'biosecurity_rating': _biosecurity,
      'management_rating': _management,
      'technical_support_rating': _technical,
      'economic_solvency_rating': _economic,
      'disease_present': _diseasePresent,
      if (_diseasePresent && _diseaseDetails.text.trim().isNotEmpty)
        'disease_details': _diseaseDetails.text.trim(),
      if (_problems.text.trim().isNotEmpty) 'problems': _problems.text.trim(),
      if (_recommendation.text.trim().isNotEmpty)
        'recommendation': _recommendation.text.trim(),
      if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
      'status': 'submitted',
      if (metrics.isNotEmpty) 'metrics': metrics,
    };

    final result = await _service.createFarmSurvey(payload);
    if (!mounted) return;
    if (!result.success || result.data == null) {
      setState(() => _submitting = false);
      _snack(result.message ?? 'Could not save survey.');
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
    _snack('Farm survey saved.');
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

  Widget _ratingRow(String label, int value, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: $value',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          Slider(
            value: value.toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            label: '$value',
            activeColor: AppColors.accent,
            onChanged: (v) => onChanged(v.round()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          GradientScreenHeader(
            title: 'Farm Survey',
            subtitle: widget.party.displayName,
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
                        _sectionTitle('Farm basics'),
                        _label('Survey type'),
                        DropdownButtonFormField<String>(
                          initialValue: _surveyType,
                          decoration: _decoration(),
                          items: _surveyTypes
                              .map(
                                (t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(t),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _surveyType = v);
                          },
                        ),
                        const SizedBox(height: 14),
                        _label('Farm type'),
                        TextField(
                          controller: _farmType,
                          decoration:
                              _decoration(hint: 'e.g. Broiler, Layer'),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _label('Bird capacity'),
                                  TextField(
                                    controller: _birdCapacity,
                                    keyboardType: TextInputType.number,
                                    decoration: _decoration(),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _label('Current birds'),
                                  TextField(
                                    controller: _currentBirds,
                                    keyboardType: TextInputType.number,
                                    decoration: _decoration(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _label('Housing type'),
                        TextField(
                          controller: _housing,
                          decoration:
                              _decoration(hint: 'e.g. Open / Closed shed'),
                        ),
                        const SizedBox(height: 14),
                        _label('Feed brand'),
                        TextField(
                          controller: _feedBrand,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 14),
                        SearchableSelectField<MarketingDemoProduct>(
                          label: 'Chicks product',
                          icon: Icons.egg_outlined,
                          options: MarketingDemoMasters.products,
                          selected: _chicksProduct,
                          displayString: (p) => p.displayName,
                          searchText: (p) => p.searchText,
                          onSelected: (p) =>
                              setState(() => _chicksProduct = p),
                        ),
                        const SizedBox(height: 14),
                        SearchableSelectField<MarketingDemoProduct>(
                          label: 'Feed product',
                          icon: Icons.inventory_2_outlined,
                          options: MarketingDemoMasters.products,
                          selected: _feedProduct,
                          displayString: (p) => p.displayName,
                          searchText: (p) => p.searchText,
                          onSelected: (p) => setState(() => _feedProduct = p),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionTitle('Flock performance'),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _label('Age (days)'),
                                  TextField(
                                    controller: _ageDays,
                                    keyboardType: TextInputType.number,
                                    decoration: _decoration(),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _label('Quantity'),
                                  TextField(
                                    controller: _quantity,
                                    keyboardType: TextInputType.number,
                                    decoration: _decoration(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _label('Mortality qty'),
                                  TextField(
                                    controller: _mortality,
                                    keyboardType: TextInputType.number,
                                    decoration: _decoration(),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _label('Chicks brand'),
                                  TextField(
                                    controller: _chicksBrand,
                                    decoration: _decoration(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _label('Total feed (kg)'),
                                  TextField(
                                    controller: _totalFeed,
                                    keyboardType: TextInputType.number,
                                    decoration: _decoration(),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _label('Avg feed (kg)'),
                                  TextField(
                                    controller: _avgFeed,
                                    keyboardType: TextInputType.number,
                                    decoration: _decoration(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _label('FCR'),
                                  TextField(
                                    controller: _fcr,
                                    keyboardType: TextInputType.number,
                                    decoration: _decoration(),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _label('Body weight (kg)'),
                                  TextField(
                                    controller: _bodyWeight,
                                    keyboardType: TextInputType.number,
                                    decoration: _decoration(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _label('Uniformity (%)'),
                        TextField(
                          controller: _uniformity,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Production (%)'),
                        TextField(
                          controller: _productionPercent,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        SearchableSelectField<MarketingDemoNamed>(
                          label: 'Quantity unit',
                          icon: Icons.straighten,
                          options: MarketingDemoMasters.units,
                          selected: _quantityUnit,
                          displayString: (u) => u.displayName,
                          searchText: (u) => u.searchText,
                          onSelected: (u) =>
                              setState(() => _quantityUnit = u),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionTitle('Ratings (1–5)'),
                        _ratingRow(
                          'Biosecurity',
                          _biosecurity,
                          (v) => setState(() => _biosecurity = v),
                        ),
                        _ratingRow(
                          'Management',
                          _management,
                          (v) => setState(() => _management = v),
                        ),
                        _ratingRow(
                          'Technical support',
                          _technical,
                          (v) => setState(() => _technical = v),
                        ),
                        _ratingRow(
                          'Economic solvency',
                          _economic,
                          (v) => setState(() => _economic = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionTitle('Health & notes'),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Disease present',
                            style: GoogleFonts.poppins(fontSize: 13),
                          ),
                          value: _diseasePresent,
                          activeThumbColor: AppColors.error,
                          onChanged: (v) =>
                              setState(() => _diseasePresent = v),
                        ),
                        if (_diseasePresent) ...[
                          _label('Disease details'),
                          TextField(
                            controller: _diseaseDetails,
                            maxLines: 2,
                            decoration: _decoration(),
                          ),
                          const SizedBox(height: 12),
                        ],
                        _label('Problems'),
                        TextField(
                          controller: _problems,
                          maxLines: 2,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Recommendation'),
                        TextField(
                          controller: _recommendation,
                          maxLines: 2,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
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
                        _sectionTitle('Extra metrics'),
                        _label('Flock age (days)'),
                        TextField(
                          controller: _flockAge,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Mortality (%)'),
                        TextField(
                          controller: _mortalityPct,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Feed bag stock'),
                        TextField(
                          controller: _feedBags,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Cultivated land (acre)'),
                        TextField(
                          controller: _landArea,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Monthly fertilizer (kg)'),
                        TextField(
                          controller: _fertilizerKg,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Daily egg production'),
                        TextField(
                          controller: _dailyEggs,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Cracked egg (%)'),
                        TextField(
                          controller: _crackedEgg,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(),
                        ),
                        const SizedBox(height: 12),
                        _label('Pond area (decimal)'),
                        TextField(
                          controller: _pondArea,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(),
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
                        const SizedBox(height: 24),
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
                                    'Submit survey',
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
