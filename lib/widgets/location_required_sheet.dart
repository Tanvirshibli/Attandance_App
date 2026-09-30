import 'package:flutter/material.dart';

import '../services/location_gate_service.dart';
import 'ui/ui.dart';

/// The blocking sheet shown when location cannot be captured.
///
/// Deliberately not a dialog: a dialog can be dismissed with the back button,
/// and the whole point of this screen is that there is no way past it without
/// either fixing the setting or signing out. [PopScope] enforces that.
class LocationRequiredSheet extends StatefulWidget {
  const LocationRequiredSheet({
    super.key,
    required this.result,
    required this.onSignOut,
    required this.onRecheck,
  });

  final LocationGateResult result;

  /// Clears the session and returns to the login screen.
  final Future<void> Function() onSignOut;

  /// Re-runs the check, called after the user returns from Settings.
  final Future<void> Function() onRecheck;

  @override
  State<LocationRequiredSheet> createState() => _LocationRequiredSheetState();
}

class _LocationRequiredSheetState extends State<LocationRequiredSheet> {
  static const LocationGateService _service = LocationGateService();

  bool _busy = false;

  Future<void> _openSettings() async {
    setState(() => _busy = true);

    try {
      await _service.openSettings(widget.result);
    } catch (_) {
      // Settings can refuse to open on some OEM builds. Nothing useful to say
      // here — the recheck below still lets them recover.
    }

    if (!mounted) return;
    setState(() => _busy = false);

    // The user is most likely already back from Settings by now, and a fix made
    // there is only visible after a fresh check.
    await widget.onRecheck();
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    await widget.onSignOut();
    // No setState afterwards: on success the guard swaps the whole tree, and on
    // failure the guard replaces this sheet with a fresh one.
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Center(
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      AppIcons.geo,
                      size: 44,
                      color: AppColors.error,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.xl),
                Text(
                  'Location is required',
                  textAlign: TextAlign.center,
                  style: AppType.h2.copyWith(color: AppColors.ink),
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  result.reason,
                  textAlign: TextAlign.center,
                  style: AppType.body.copyWith(color: AppColors.inkMuted),
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  'Attendance is recorded with a location stamp, so the app '
                  'cannot capture a check-in or check-out without it.',
                  textAlign: TextAlign.center,
                  style: AppType.meta.copyWith(color: AppColors.inkMuted),
                ),
                const Spacer(),
                AppButton(
                  label: result.opensLocationSettings
                      ? 'Turn on Location'
                      : 'Open app settings',
                  icon: AppIcons.settings,
                  busy: _busy,
                  onPressed: _busy ? null : _openSettings,
                ),
                const SizedBox(height: AppSpace.sm),
                AppButton(
                  label: 'Try again',
                  kind: AppButtonKind.secondary,
                  onPressed: _busy ? null : () async => widget.onRecheck(),
                ),
                const SizedBox(height: AppSpace.sm),
                AppButton(
                  label: 'Sign out instead',
                  kind: AppButtonKind.ghost,
                  onPressed: _busy ? null : _signOut,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}