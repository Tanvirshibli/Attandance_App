class GeoPing {
  const GeoPing({
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
    this.address,
    this.accuracyM,
    this.uploaded = false,
  });

  final double latitude;
  final double longitude;
  final DateTime capturedAt;
  final String? address;
  final double? accuracyM;
  final bool uploaded;

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'capturedAt': capturedAt.toIso8601String(),
        'address': address,
        if (accuracyM != null) 'accuracyM': accuracyM,
        'uploaded': uploaded,
      };

  factory GeoPing.fromJson(Map<String, dynamic> json) {
    return GeoPing(
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      capturedAt: DateTime.tryParse(json['capturedAt']?.toString() ?? '') ??
          DateTime.now(),
      address: json['address']?.toString(),
      accuracyM: json['accuracyM'] == null
          ? null
          : _toDouble(json['accuracyM']),
      uploaded: json['uploaded'] == true,
    );
  }

  static double _toDouble(Object? v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }
}
