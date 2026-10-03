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
    this.channel,
  });

  final String appId;
  final String versionName;
  final int versionCode;
  final bool forceUpdate;
  final String releaseNotes;
  final String? publishedAt;
  final Map<String, AppUpdateApkInfo> apks;

  /// Which channel published this manifest: `prod` or `beta`.
  ///
  /// Informational — the app is already pinned to one channel by the manifest
  /// URL baked in at compile time, so this never routes anything. It exists so
  /// a tester can see at a glance which feed they are on, and so a channel
  /// mismatch is visible rather than mysterious. Null on a manifest published
  /// before the channel existed.
  final String? channel;

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
      channel: json['channel']?.toString(),
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

/// Strips Flutter's split-per-ABI prefix from a build number.
///
/// A split-per-ABI build encodes the real code as `prefix + code` where the
/// prefix is 1000 (armeabi-v7a), 2000 (arm64-v8a) or 3000 (x86_64), so a
/// release published from `app-arm64-v8a-release.apk` carries 2000+N. Both
/// sides of the comparison go through this, so the prefix cancels out.
///
/// **Only those three bands are stripped.** The beta channel deliberately lives
/// at 9000+, which is not an ABI prefix: reducing it modulo 1000 would turn a
/// beta build 9108 into 108 and make it compare as a low *production* code —
/// so a tester would be offered the wrong channel's update and a production
/// manifest could look newer than a beta build. Anything outside 1000–3999 is
/// a real version code and is returned untouched.
int normalizeVersionCode(String rawBuildNumber) {
  final raw = int.tryParse(rawBuildNumber) ?? 0;
  if (raw >= 1000 && raw < 4000) return raw % 1000;
  return raw;
}

/// The lowest build number the beta channel may use.
///
/// Prod builds stay below this so the two channels can never collide on a
/// version comparison, and so release tags cannot collide either.
const int betaVersionFloor = 9000;

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
