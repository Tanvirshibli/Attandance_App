import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import '../models/app_update_manifest.dart';
import '../services/app_update_service.dart';

enum AppUpdateUiPhase {
  ready,
  downloading,
  verifying,
  installing,
  error,
}

class AppUpdateScreen extends StatefulWidget {
  const AppUpdateScreen({
    super.key,
    required this.manifest,
    required this.installedVersionCode,
  });

  final AppUpdateManifest manifest;
  final int installedVersionCode;

  @override
  State<AppUpdateScreen> createState() => _AppUpdateScreenState();
}

class _AppUpdateScreenState extends State<AppUpdateScreen> {
  final AppUpdateService _service = AppUpdateService();

  AppUpdateUiPhase _phase = AppUpdateUiPhase.ready;
  String? _errorMessage;
  int _received = 0;
  int _total = 0;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Icon(Icons.system_update_alt, size: 56, color: AppColors.primary),
                const SizedBox(height: 20),
                Text(
                  'Update required',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'v${widget.manifest.versionName} (build ${widget.manifest.versionCode}) is available.\n'
                  'You are on build ${widget.installedVersionCode}.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                if (widget.manifest.releaseNotes.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.shadow.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Text(
                      widget.manifest.releaseNotes,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (_phase == AppUpdateUiPhase.downloading) ...[
                  LinearProgressIndicator(
                    value: _total > 0 ? _received / _total : null,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${formatBytes(_received)} / ${formatBytes(_total)}  (${downloadPercent(_received, _total)}%)',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Downloading update…',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ] else if (_phase == AppUpdateUiPhase.verifying) ...[
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 12),
                  Text(
                    'Verifying download…',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 13),
                  ),
                ] else if (_phase == AppUpdateUiPhase.installing) ...[
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 12),
                  Text(
                    'Opening installer…\nTap Install on the system dialog.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ] else if (_phase == AppUpdateUiPhase.error) ...[
                  Text(
                    _errorMessage ?? 'Update failed.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: AppColors.error,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _startDownload,
                    child: Text(
                      'Retry download',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                  ),
                ] else ...[
                  FilledButton(
                    onPressed: _startDownload,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      'Download update',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (widget.manifest.forceUpdate)
                  Text(
                    'You must install this update to continue using the app.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startDownload() async {
    if (!Platform.isAndroid) {
      setState(() {
        _phase = AppUpdateUiPhase.error;
        _errorMessage = 'Updates are only supported on Android.';
      });
      return;
    }

    setState(() {
      _phase = AppUpdateUiPhase.downloading;
      _errorMessage = null;
      _received = 0;
      _total = widget.manifest.resolveApk(
            preferredAbi: 'arm64-v8a',
          )?.sizeBytes ??
          0;
    });

    try {
      final file = await _service.downloadApk(
        manifest: widget.manifest,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total;
          });
        },
      );

      if (!mounted) return;
      setState(() => _phase = AppUpdateUiPhase.installing);

      await _service.installApk(file);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = AppUpdateUiPhase.error;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }
}
