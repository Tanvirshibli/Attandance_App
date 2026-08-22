import 'package:flutter/material.dart';

import '../../models/marketing_models.dart';
import 'visit_form_shared.dart';

/// Dealer party visit form (stock/order observations — not farm survey).
class DealerVisitFormScreen extends StatelessWidget {
  const DealerVisitFormScreen({super.key, required this.party});

  final Party party;

  @override
  Widget build(BuildContext context) {
    return SharedVisitFormScreen.dealer(party: party);
  }
}
