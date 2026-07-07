class EndpointDefinition {
  const EndpointDefinition({
    required this.method,
    required this.url,
    required this.backend,
    this.meta,
  });

  final String method;
  final String url;
  final String backend;
  final Map<String, dynamic>? meta;

  factory EndpointDefinition.fromJson(Map<String, dynamic> json) {
    return EndpointDefinition(
      method: json['method']?.toString() ?? 'GET',
      url: json['url']?.toString() ?? '',
      backend: json['backend']?.toString() ?? '',
      meta: json['meta'] is Map<String, dynamic>
          ? json['meta'] as Map<String, dynamic>
          : null,
    );
  }
}

class EndpointConfig {
  const EndpointConfig({
    required this.version,
    this.updatedAt,
    this.bases = const {},
    this.endpoints = const {},
    this.features = const {},
  });

  final int version;
  final String? updatedAt;
  final Map<String, String> bases;
  final Map<String, EndpointDefinition> endpoints;
  final Map<String, dynamic> features;

  factory EndpointConfig.fromJson(Map<String, dynamic> json) {
    final rawEndpoints = json['endpoints'];
    final endpoints = <String, EndpointDefinition>{};

    if (rawEndpoints is Map<String, dynamic>) {
      rawEndpoints.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          endpoints[key] = EndpointDefinition.fromJson(value);
        }
      });
    }

    final rawBases = json['bases'];
    final bases = <String, String>{};
    if (rawBases is Map<String, dynamic>) {
      rawBases.forEach((key, value) {
        bases[key] = value.toString();
      });
    }

    final rawFeatures = json['features'];
    final features = <String, dynamic>{};
    if (rawFeatures is Map<String, dynamic>) {
      features.addAll(rawFeatures);
    }

    return EndpointConfig(
      version: json['version'] is int
          ? json['version'] as int
          : int.tryParse(json['version']?.toString() ?? '0') ?? 0,
      updatedAt: json['updated_at']?.toString(),
      bases: bases,
      endpoints: endpoints,
      features: features,
    );
  }

  bool isFeatureEnabled(String key, {bool defaultValue = false}) {
    final value = features[key];
    if (value is bool) return value;
    return defaultValue;
  }

  int geoIntervalMinutes({int fallback = 5}) {
    final value = features['interval_minutes'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return fallback;
  }

  String? urlFor(String key) {
    final endpoint = endpoints[key];
    if (endpoint == null || endpoint.url.isEmpty) return null;
    return endpoint.url;
  }
}
