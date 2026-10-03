import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import '../models/app_update_manifest.dart';

typedef DownloadProgressCallback = void Function(int received, int total);

class AppUpdateCheckResult {
  const AppUpdateCheckResult.upToDate()
      : manifest = null,
        installedVersionCode = 0,
        errorMessage = null;

  const AppUpdateCheckResult.updateRequired({
    required this.manifest,
    required this.installedVersionCode,
  }) : errorMessage = null;

  const AppUpdateCheckResult.error(this.errorMessage)
      : manifest = null,
        installedVersionCode = 0;

  final AppUpdateManifest? manifest;
  final int installedVersionCode;
  final String? errorMessage;

  bool get needsUpdate => manifest != null;
  bool get hasError => errorMessage != null;
}

class AppUpdateService {
  AppUpdateService({Dio? dio}) : _dio = dio ?? Dio();

  static const _channel = MethodChannel('com.pphl.employee_attendance/apk_installer');

  final Dio _dio;

  Future<AppUpdateCheckResult> checkForUpdate() async {
    if (!AppConfig.updateCheckEnabled) {
      return const AppUpdateCheckResult.upToDate();
    }

    // Which feed this build watches, and where the installed build sits in its
    // channel's band. The only way to tell a beta build from a production one
    // once both are installed, and the first thing to check when a tester says
    // the update did not appear.
    if (kDebugMode) {
      debugPrint(
        'OTA channel=${AppConfig.updateChannel} '
        'manifest=${AppConfig.updateManifestUrl}',
      );
    }

    await cleanupIncompleteDownload();

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final preferredAbi = await getPreferredAbi();
      final installedCode = normalizeVersionCode(
        packageInfo.buildNumber,
        abiOffset: abiOffsetFor(preferredAbi),
      );

      final response = await _dio.get<dynamic>(
        AppConfig.updateManifestUrl,
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
          headers: const {'Cache-Control': 'no-cache'},
        ),
      );

      final manifestMap = _parseManifestMap(response.data);
      if (manifestMap == null) {
        _logInvalidManifestBody(response.data);
        return const AppUpdateCheckResult.error(
          'Could not read update manifest. Tap Retry or continue offline.',
        );
      }

      final manifest = AppUpdateManifest.fromJson(manifestMap);
      if (manifest.appId.isNotEmpty &&
          manifest.appId != AppConfig.appPackageId) {
        return const AppUpdateCheckResult.error(
          'Update manifest is for a different app.',
        );
      }

      // Taken verbatim. The manifest's version_code is written by the publish
      // script, which already subtracted the ABI offset while reading the APK, so
      // it is already the base build number. Running it through
      // normalizeVersionCode again would subtract a further offset from a
      // legitimate four-digit beta number.
      final remoteCode = manifest.versionCode;
      if (!isUpdateRequired(
        installedVersionCode: installedCode,
        remoteVersionCode: remoteCode,
      )) {
        return const AppUpdateCheckResult.upToDate();
      }

      return AppUpdateCheckResult.updateRequired(
        manifest: manifest,
        installedVersionCode: installedCode,
      );
    } on DioException catch (e) {
      debugPrint('AppUpdateService.checkForUpdate: $e');
      return AppUpdateCheckResult.error(
        e.message ?? 'Could not check for updates. Check your internet connection.',
      );
    } catch (e) {
      debugPrint('AppUpdateService.checkForUpdate: $e');
      return AppUpdateCheckResult.error('Could not check for updates.');
    }
  }

  Future<String> getPreferredAbi() async {
    if (!Platform.isAndroid) return 'arm64-v8a';
    try {
      final abi = await _channel.invokeMethod<String>('getPreferredAbi');
      if (abi != null && abi.isNotEmpty) return abi;
    } catch (e) {
      debugPrint('AppUpdateService.getPreferredAbi: $e');
    }
    return 'arm64-v8a';
  }

  Future<File> downloadApk({
    required AppUpdateManifest manifest,
    required DownloadProgressCallback onProgress,
  }) async {
    await cleanupIncompleteDownload();

    final abi = await getPreferredAbi();
    final apkInfo = manifest.resolveApk(preferredAbi: abi);
    if (apkInfo == null || apkInfo.url.isEmpty) {
      throw Exception('No APK available for this device ($abi).');
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/app-update.apk');
    if (await file.exists()) {
      await file.delete();
    }

    await _dio.download(
      apkInfo.url,
      file.path,
      onReceiveProgress: (received, total) {
        final effectiveTotal = total > 0 ? total : apkInfo.sizeBytes;
        onProgress(received, effectiveTotal);
      },
      options: Options(
        receiveTimeout: const Duration(minutes: 30),
        sendTimeout: const Duration(minutes: 30),
      ),
    );

    final bytes = await file.readAsBytes();
    if (apkInfo.sha256.isNotEmpty) {
      final digest = sha256.convert(bytes).toString();
      if (digest != apkInfo.sha256.toLowerCase()) {
        await file.delete();
        throw Exception('Download verification failed. Please try again.');
      }
    }

    return file;
  }

  Future<void> installApk(File apkFile) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('APK install is only supported on Android.');
    }
    await _channel.invokeMethod<void>('installApk', {
      'path': apkFile.path,
    });
  }

  Future<void> cleanupIncompleteDownload() async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/app-update.apk');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('AppUpdateService.cleanupIncompleteDownload: $e');
    }
  }

  void _logInvalidManifestBody(dynamic data) {
    final preview = data == null
        ? 'null'
        : data is String
            ? (data.length > 200 ? data.substring(0, 200) : data)
            : data.toString();
    debugPrint(
      'AppUpdateService.checkForUpdate: invalid manifest body '
      'url=${AppConfig.updateManifestUrl} type=${data.runtimeType} preview=$preview',
    );
  }
}

Map<String, dynamic>? _parseManifestMap(dynamic data) {
  if (data is Map<String, dynamic>) {
    return data;
  }
  if (data is Map) {
    return Map<String, dynamic>.from(data);
  }
  if (data is String) {
    try {
      var trimmed = data.trimLeft();
      if (trimmed.startsWith('\uFEFF')) {
        trimmed = trimmed.substring(1);
      }
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }
  }
  return null;
}

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  if (unit == 0) return '${value.toInt()} ${units[unit]}';
  return '${value.toStringAsFixed(1)} ${units[unit]}';
}

int downloadPercent(int received, int total) {
  if (total <= 0) return 0;
  return ((received / total) * 100).clamp(0, 100).round();
}
