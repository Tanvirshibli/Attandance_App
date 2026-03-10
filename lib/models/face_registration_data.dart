class FaceRegistrationData {
  const FaceRegistrationData({
    required this.avgEmbedding,
    required this.captureEmbeddings,
    required this.adaptiveEmbeddings,
    required this.captureCount,
    this.registrationQuality,
    this.registeredAt,
    this.status,
  });

  final List<double> avgEmbedding;
  final List<List<double>> captureEmbeddings;
  final List<List<double>> adaptiveEmbeddings;
  final int captureCount;
  final Map<String, dynamic>? registrationQuality;
  final String? registeredAt;
  final String? status;

  bool get hasData => avgEmbedding.isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'avgEmbedding': avgEmbedding,
      'captureEmbeddings': captureEmbeddings,
      'adaptiveEmbeddings': adaptiveEmbeddings,
      'captureCount': captureCount,
      'registrationQuality': registrationQuality,
      'registeredAt': registeredAt,
    };
  }

  static FaceRegistrationData? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return null;
    }

    final avg = _toDoubleList(raw['avgEmbedding']);
    if (avg.isEmpty) {
      return null;
    }

    return FaceRegistrationData(
      avgEmbedding: avg,
      captureEmbeddings: _toDoubleMatrix(raw['captureEmbeddings']),
      adaptiveEmbeddings: _toDoubleMatrix(raw['adaptiveEmbeddings']),
      captureCount: _toInt(raw['captureCount']) ?? 0,
      registrationQuality: raw['registrationQuality'] is Map<String, dynamic>
          ? raw['registrationQuality'] as Map<String, dynamic>
          : null,
      registeredAt: raw['registeredAt']?.toString(),
      status: raw['status']?.toString(),
    );
  }

  static List<double> _toDoubleList(Object? raw) {
    if (raw is! List) {
      return const [];
    }

    final output = <double>[];
    for (final value in raw) {
      if (value is num) {
        output.add(value.toDouble());
      } else {
        final parsed = double.tryParse(value.toString());
        if (parsed != null) {
          output.add(parsed);
        }
      }
    }
    return output;
  }

  static List<List<double>> _toDoubleMatrix(Object? raw) {
    if (raw is! List) {
      return const [];
    }

    final output = <List<double>>[];
    for (final row in raw) {
      output.add(_toDoubleList(row));
    }
    return output.where((row) => row.isNotEmpty).toList();
  }

  static int? _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
