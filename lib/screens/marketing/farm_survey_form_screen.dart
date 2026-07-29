import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../config/theme.dart';
import '../../models/marketing_models.dart';
import '../../services/auth_service.dart';
import '../../services/marketing_service.dart';
import '../../widgets/gradient_screen_header.dart';
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
  final _flockAge = TextEditingController();
  final _mortality = TextEditingController();
  final _feedBags = TextEditingController();

  bool _submitting = false;
  final List<XFile> _photos = [];

  @override
  void dispose() {
    _farmType.dispose();
    _birdCapacity.dispose();
    _currentBirds.dispose();
    _housing.dispose();
    _feedBrand.dispose();
    _notes.dispose();
    _flockAge.dispose();
    _mortality.dispose();
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
    void addMetric(String key, String label, TextEditingController c, {String? unit}) {
      final raw = c.text.trim();
      if (raw.isEmpty) return;
      final numVal = double.tryParse(raw);
      metrics.add({
        'metric_key': key,
        'metric_label': label,
        if (numVal != null) 'value_number': numVal else 'value_text': raw,
        'unit': ?unit,
      });
    }

    addMetric('flock_age_days', 'Flock age', _flockAge, unit: 'days');
    addMetric('mortality_pct', 'Mortality', _mortality, unit: '%');
    addMetric('feed_bag_stock', 'Feed bag stock', _feedBags, unit: 'bags');

    final payload = <String, dynamic>{
      'party_id': widget.party.id,
      'employee_id': employeeId,
      'visit_id': ?widget.visitId,
      'survey_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      if (_farmType.text.trim().isNotEmpty) 'farm_type': _farmType.text.trim(),
      if (_birdCapacity.text.trim().isNotEmpty)
        'bird_capacity': double.tryParse(_birdCapacity.text.trim()),
      if (_currentBirds.text.trim().isNotEmpty)
        'current_birds': double.tryParse(_currentBirds.text.trim()),
      if (_housing.text.trim().isNotEmpty)
        'housing_type': _housing.text.trim(),
      if (_feedBrand.text.trim().isNotEmpty)
        'feed_brand': _feedBrand.text.trim(),
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
        attachableType: 'farm_survey',
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
              child: SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label('Farm type'),
                    TextField(
                      controller: _farmType,
                      decoration: _decoration(hint: 'e.g. Broiler, Layer'),
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
                      decoration: _decoration(hint: 'e.g. Open / Closed shed'),
                    ),
                    const SizedBox(height: 14),
                    _label('Feed brand'),
                    TextField(
                      controller: _feedBrand,
                      decoration: _decoration(),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Metrics',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _label('Flock age (days)'),
                    TextField(
                      controller: _flockAge,
                      keyboardType: TextInputType.number,
                      decoration: _decoration(),
                    ),
                    const SizedBox(height: 12),
                    _label('Mortality (%)'),
                    TextField(
                      controller: _mortality,
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
                    const SizedBox(height: 14),
                    _label('Notes'),
                    TextField(
                      controller: _notes,
                      maxLines: 2,
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
            ),
          ),
        ],
      ),
    );
  }
}
