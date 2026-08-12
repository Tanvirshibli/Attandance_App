/// Parsed sales auth-wise payment report failure for hub UI.
class PaymentReportFailure {
  const PaymentReportFailure({
    required this.headline,
    this.context,
    this.actionHint,
    this.isSetupIssue = false,
    this.statusCode,
  });

  final String headline;
  final String? context;
  final String? actionHint;
  final bool isSetupIssue;
  final int? statusCode;
}
