import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/app_update_service.dart';
import '../screens/app_bootstrap.dart';
import '../screens/app_update_screen.dart';

/// Checks GitHub OTA manifest on cold start and blocks the app when an update
/// is required.
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key});

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  final AppUpdateService _updateService = AppUpdateService();

  bool _skipUpdateCheck = false;
  late Future<AppUpdateCheckResult> _checkFuture;

  @override
  void initState() {
    super.initState();
    _checkFuture = _updateService.checkForUpdate();
  }

  void _retryCheck() {
    setState(() {
      _checkFuture = _updateService.checkForUpdate();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.updateCheckEnabled || _skipUpdateCheck) {
      return const AppBootstrap();
    }

    return FutureBuilder<AppUpdateCheckResult>(
      future: _checkFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Checking for updates…'),
                ],
              ),
            ),
          );
        }

        final result = snapshot.data!;

        if (result.needsUpdate && result.manifest != null) {
          return AppUpdateScreen(
            manifest: result.manifest!,
            installedVersionCode: result.installedVersionCode,
          );
        }

        if (result.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      result.errorMessage ?? 'Could not check for updates.',
                      textAlign: TextAlign.center,
                    ),
                    if (AppConfig.updateManifestUrl.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        AppConfig.updateManifestUrl,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.6),
                            ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _retryCheck,
                      child: const Text('Retry'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        setState(() => _skipUpdateCheck = true);
                      },
                      child: const Text('Continue offline'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return const AppBootstrap();
      },
    );
  }
}
