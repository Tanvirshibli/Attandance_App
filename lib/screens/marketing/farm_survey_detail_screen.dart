import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/theme.dart';
import '../../models/marketing_models.dart';
import '../../services/marketing_service.dart';
import '../../widgets/api_empty_state.dart';
import '../../widgets/gradient_screen_header.dart';
import '../../widgets/marketing_photo_widgets.dart';
import '../../widgets/section_card.dart';

class FarmSurveyDetailScreen extends StatefulWidget {
  const FarmSurveyDetailScreen({
    super.key,
    required this.surveyId,
    this.initial,
  });

  final int surveyId;
  final FarmSurvey? initial;

  @override
  State<FarmSurveyDetailScreen> createState() => _FarmSurveyDetailScreenState();
}

class _FarmSurveyDetailScreenState extends State<FarmSurveyDetailScreen> {
  final MarketingService _service = MarketingService();
  FarmSurvey? _survey;
  List<Attachment> _attachments = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _survey = widget.initial;
    _attachments = widget.initial?.attachments ?? const [];
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _service.getFarmSurvey(widget.surveyId);
    if (!mounted) return;
    if (!result.success || result.data == null) {
      setState(() {
        _error = result.message ?? 'Could not load report.';
        _loading = false;
      });
      return;
    }
    var survey = result.data!;
    var attachments = survey.attachments;
    if (attachments.isEmpty) {
      final listed = await _service.listAttachments(
        attachableType: 'survey',
        attachableId: survey.id,
      );
      if (listed.success && listed.data != null) {
        attachments = listed.data!;
      }
    }
    if (!mounted) return;
    setState(() {
      _survey = survey;
      _attachments = attachments;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final survey = _survey;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: GradientScreenHeader(
                title: 'Farm visit report',
                subtitle: survey?.displayTitle ?? 'Loading…',
              ),
            ),
            if (_loading && survey == null)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && survey == null)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ApiEmptyState(
                      icon: Icons.error_outline,
                      title: 'Could not load',
                      subtitle: _error,
                      onRetry: _load,
                    ),
                  ),
                ),
              )
            else if (survey != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                sliver: SliverToBoxAdapter(
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _row('Date', survey.surveyDate),
                        _row('Visit type', survey.extraData?['visit_type_label']?.toString()),
                        _row('Farm', survey.partyName),
                        _row('Dealer', survey.dealerPartyName),
                        _row('Farming years', _n(survey.farmingYears)),
                        _row('Hatch date', survey.hatchDate),
                        _row('Receiving date', survey.receivingDate),
                        _row('Receiving time', survey.receivingTime),
                        _row('Breed', survey.breed),
                        _row('DOC company', survey.docCompany),
                        _row('Feed company', survey.feedCompany),
                        _row('Quantity', _n(survey.quantity)),
                        _row('Age', survey.ageDays?.toString()),
                        _row('Total mortality', _n(survey.totalMortality)),
                        _row('Present mortality', _n(survey.presentMortality)),
                        _row('Mortality %', _n(survey.mortalityPercent)),
                        _row('Rest of bird', _n(survey.restOfBirds)),
                        _row('Total feed intake', _n(survey.totalFeedIntakeKg)),
                        _row('Av. feed intake', _n(survey.avgFeedIntakeKg)),
                        _row('Production% / FCR', _productionFcrDisplay(survey)),
                        _row('Total body weight', _n(survey.totalBodyWeightKg)),
                        _row('Av. B/W', _n(survey.avgBodyWeightKg)),
                        _row('Per bag weight', _n(survey.bagWeightKg)),
                        _row('Shed design', survey.shedDesign),
                        _row('Curtain', survey.curtainType),
                        _row('Floor', survey.floorType),
                        _row('Feeders', _n(survey.feederQty)),
                        _row('Drinkers', _n(survey.drinkerQty)),
                        _row('Av. temperature', survey.extraData?['avg_temperature_note']?.toString() ?? _n(survey.avgTemperature)),
                        _row('Space', survey.spaceNote),
                        _row('Biosecurity', survey.biosecurityRating?.toString()),
                        _row('Uniformity', _n(survey.uniformityPercent)),
                        _row('Management', survey.managementRating?.toString()),
                        _row('Diseases', survey.diseaseDetails),
                        _row(
                          'Technical support',
                          survey.technicalSupportRating?.toString(),
                        ),
                        _row('Problem facing', survey.problems),
                        _row(
                          'Economical solvency',
                          survey.economicSolvencyRating?.toString(),
                        ),
                        _row('Remarks', survey.notes),
                        _row('Comments', survey.comments),
                        _row('Territory', survey.territory),
                        _row('Zone', survey.zone),
                        _row(
                          'Reporting designation',
                          survey.extraData?['reporting_officer_designation']?.toString(),
                        ),
                        _photoSection(survey),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String? _n(num? v) => v?.toString();

  String? _productionFcrDisplay(FarmSurvey survey) {
    final note = survey.extraData?['production_fcr_note']?.toString();
    if (note != null && note.trim().isNotEmpty) return note.trim();
    final prod = survey.productionPercent;
    final fcr = survey.fcr;
    if (prod != null && fcr != null) return '$prod% / $fcr';
    if (fcr != null) return fcr.toString();
    if (prod != null) return '$prod%';
    return null;
  }

  Widget _photoSection(FarmSurvey survey) {
    return MarketingPhotoGrid(attachments: _attachments);
  }

  Widget _row(String label, String? value) {
    if (value == null || value.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
