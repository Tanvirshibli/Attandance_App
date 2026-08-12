class AppUpdateApkInfo {
  const AppUpdateApkInfo({
    required this.url,
    required this.sizeBytes,
    required this.sha256,
  });

  final String url;
  final int sizeBytes;
  final String sha256;

  factory AppUpdateApkInfo.fromJson(Map<String, dynamic> json) {
    return AppUpdateApkInfo(
      url: json['url']?.toString() ?? '',
      sizeBytes: _parseInt(json['size_bytes']),
      sha256: json['sha256']?.toString().toLowerCase() ?? '',
    );
  }
}

class AppUpdateManifest {
  const AppUpdateManifest({
    required this.appId,
    required this.versionName,
    required this.versionCode,
    required this.forceUpdate,
    required this.releaseNotes,
    required this.publishedAt,
    required this.apks,
  });

  final String appId;
  final String versionName;
  final int versionCode;
  final bool forceUpdate;
  final String releaseNotes;
  final String? publishedAt;
  final Map<String, AppUpdateApkInfo> apks;

  factory AppUpdateManifest.fromJson(Map<String, dynamic> json) {
    final apksRaw = json['apks'];
    final apks = <String, AppUpdateApkInfo>{};
    if (apksRaw is Map) {
      for (final entry in apksRaw.entries) {
        final value = entry.value;
        if (value is Map<String, dynamic>) {
          apks[entry.key.toString()] = AppUpdateApkInfo.fromJson(value);
        } else if (value is Map) {
          apks[entry.key.toString()] =
              AppUpdateApkInfo.fromJson(Map<String, dynamic>.from(value));
        }
      }
    }

    return AppUpdateManifest(
      appId: json['app_id']?.toString() ?? '',
      versionName: json['version_name']?.toString() ?? '',
      versionCode: _parseInt(json['version_code']),
      forceUpdate: json['force_update'] == true,
      releaseNotes: json['release_notes']?.toString() ?? '',
      publishedAt: json['published_at']?.toString(),
      apks: apks,
    );
  }

  AppUpdateApkInfo? apkForAbi(String abi) => apks[abi];

  /// Picks arm64-v8a when available, otherwise armeabi-v7a.
  AppUpdateApkInfo? resolveApk({required String preferredAbi}) {
    final direct = apks[preferredAbi];
    if (direct != null && direct.url.isNotEmpty) return direct;
    if (apks['arm64-v8a']?.url.isNotEmpty == true) return apks['arm64-v8a'];
    if (apks['armeabi-v7a']?.url.isNotEmpty == true) return apks['armeabi-v7a'];
    for (final apk in apks.values) {
      if (apk.url.isNotEmpty) return apk;
    }
    return null;
  }
}

int normalizeVersionCode(String rawBuildNumber) {
  final raw = int.tryParse(rawBuildNumber) ?? 0;
  if (raw >= 1000) return raw % 1000;
  return raw;
}

bool isUpdateRequired({
  required int installedVersionCode,
  required int remoteVersionCode,
}) {
  return remoteVersionCode > installedVersionCode;
}

int _parseInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
