import 'package:flutter/material.dart';

import '../../models/marketing_models.dart';
import 'visit_form_shared.dart';

/// Market-scoped visit form; user picks which party in the market is visited.
class MarketVisitFormScreen extends StatelessWidget {
  const MarketVisitFormScreen({
    super.key,
    required this.market,
    required this.partiesInMarket,
  });

  final Market market;
  final List<Party> partiesInMarket;

  @override
  Widget build(BuildContext context) {
    return SharedVisitFormScreen.market(
      market: market,
      partiesInMarket: partiesInMarket,
    );
  }
}
