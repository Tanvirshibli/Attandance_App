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

/// Undoes Flutter's split-per-ABI offset from a build number.
///
/// A split-per-ABI build **adds** the offset to the base: armeabi-v7a is
/// `base + 1000`, arm64-v8a `base + 2000`, x86_64 `base + 3000`. Both sides of
/// the update comparison go through this, so the offset cancels out.
///
/// **Subtraction, not modulo.** `raw % 1000` agrees by coincidence for a
/// three-digit base (2104 % 1000 = 104) and silently breaks the moment the base
/// has four digits: a beta build 9008 is `11008` on arm64, and `11008 % 1000` is
/// 8 — so the beta manifest would advertise build 8 and every tester would read
/// it as "up to date".
///
/// [abiOffset] is the calling APK's own offset, read from its ABI via
/// [abiOffsetFor]. There is deliberately no guessing fallback: with no offset
/// supplied this returns the value unchanged, because subtracting a guessed
/// offset from an unknown base is worse than subtracting nothing — 11008 would
/// become 6008 or 8008 depending on which offset was assumed, and the resulting
/// comparison would be wrong in a way nothing would surface.
int normalizeVersionCode(String rawBuildNumber, {int abiOffset = 0}) {
  final raw = int.tryParse(rawBuildNumber) ?? 0;
  if (abiOffset > 0 && raw >= abiOffset) return raw - abiOffset;
  return raw;
}

/// The offset Flutter added to [abi], or 0 when it is not a known split ABI.
///
/// Read from the device's own ABI rather than assumed, because assuming is what
/// produced the modulo bug above.
int abiOffsetFor(String? abi) => switch (abi) {
  'armeabi-v7a' => 1000,
  'arm64-v8a' => 2000,
  'x86_64' => 3000,
  _ => 0,
};

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
