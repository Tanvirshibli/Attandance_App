import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/app_update_service.dart';
import '../screens/app_bootstrap.dart';
import '../screens/app_update_screen.dart';

/// Checks GitHub OTA manifest on cold start and blocks the app when an update
/// is required.
///
/// The check runs alongside the app rather than in front of it. It used to await
/// the manifest before rendering anything at all, which meant every cold start
/// opened with a "Checking for updates…" spinner held open by a GitHub request —
/// on the office wifi that is a second of dead screen, and on a phone data
/// connection it is a lot longer. The app now renders immediately and only
/// swaps in the update screen if a newer build actually turns up.
///
/// A failed check is not surfaced as a blocking error either. The app is
/// perfectly usable offline; refusing to open because a version lookup failed
/// would be a worse trade than possibly running one build behind.
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key});

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  final AppUpdateService _updateService = AppUpdateService();

  /// Null until the manifest has been read. Rendering `AppBootstrap` while this
  /// is null is the point of the whole widget.
  AppUpdateCheckResult? _result;

  @override
  void initState() {
    super.initState();

    if (!AppConfig.updateCheckEnabled) {
      return;
    }

    unawaited(_check());
  }

  Future<void> _check() async {
    try {
      final result = await _updateService.checkForUpdate();

      // The gate is usually replaced by the app-update screen rather than
      // rebuilt, but a check that resolves after a sign-out still has to be
      // able to set state safely.
      if (!mounted) return;

      setState(() => _result = result);
    } catch (error) {
      debugPrint('Update check failed, continuing without it: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    if (!AppConfig.updateCheckEnabled) {
      return const AppBootstrap();
    }

    if (result == null) {
      return const AppBootstrap();
    }

    if (result.needsUpdate && result.manifest != null) {
      return AppUpdateScreen(
        manifest: result.manifest!,
        installedVersionCode: result.installedVersionCode,
      );
    }

    // Nothing newer, or the check failed: either way the app is what should be
    // on screen, and it is already rendered underneath.
    return const AppBootstrap();
  }
}