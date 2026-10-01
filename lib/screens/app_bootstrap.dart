import 'dart:async';

import 'package:flutter/material.dart';

import 'login_screen.dart';
import 'main_shell.dart';
import 'permissions_gate_screen.dart';
import 'server_bootstrap_screen.dart';
import '../services/app_permissions_service.dart';
import '../services/auth_service.dart';
import '../services/endpoint_config_service.dart';
import '../services/face_recognition_service.dart';
import '../services/fcm_wake_handler.dart';
import '../services/geo_tracking_service.dart';
import '../services/permission_service.dart';

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap>
    with WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  final FaceRecognitionService _faceRecognitionService = FaceRecognitionService();
  final EndpointConfigService _configService = EndpointConfigService.instance;
  final AppPermissionsService _permissions = AppPermissionsService.instance;

  bool? _permissionsOk;
  Future<_BootstrapState>? _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ensurePermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _ensurePermissions();
    }
  }

  Future<void> _ensurePermissions() async {
    final granted = await _permissions.areAllGranted();
    if (!mounted) return;

    if (!granted) {
      setState(() {
        _permissionsOk = false;
        _bootstrapFuture = null;
      });
      return;
    }

    if (_permissionsOk == true && _bootstrapFuture != null) {
      return;
    }

    setState(() {
      _permissionsOk = true;
      _bootstrapFuture = _prepare();
    });
    unawaited(_enableGeoAfterPermissions());
  }

  void _onPermissionsGranted() {
    if (_permissionsOk == true && _bootstrapFuture != null) {
      return;
    }
    setState(() {
      _permissionsOk = true;
      _bootstrapFuture = _prepare();
    });
    unawaited(_enableGeoAfterPermissions());
  }

  Future<void> _enableGeoAfterPermissions() async {
    try {
      await GeoTrackingService().ensureEnabledIfAllowed();
    } catch (_) {}
  }

  Future<_BootstrapState> _prepare() async {
    final hasBootstrap = await _configService.hasBootstrapUrl();
    if (!hasBootstrap) {
      return _BootstrapState.needsBootstrap;
    }

    await _configService.getConfig();

    final isLoggedIn = await _authService.isLoggedIn();
    if (!isLoggedIn) {
      _faceRecognitionService.clearRegistrationMemory();
      return _BootstrapState.needsLogin;
    }

    // The session is valid, which is the only thing this decision needs. The
    // profile, the geo timer and the push token are all downstream of that and
    // none of them gates rendering the shell, so they run alongside it rather
    // than in front of it. Awaiting get-my-info here put a 45s request in front
    // of the first frame on every cold start.
    unawaited(_warmAuthenticatedSession());

    return _BootstrapState.authenticated;
  }

  /// Everything the app needs once the user is known to be signed in, none of
  /// which the shell cannot render without.
  Future<void> _warmAuthenticatedSession() async {
    try {
      final profile = await _authService.getCurrentUserProfile();
      _faceRecognitionService.hydrateRegistration(profile?.faceRegistration);
      // Redundant since PermissionService.update() moved into
      // AuthService.getCurrentUserProfile(), which this await already calls.
      // Kept deliberately: it is idempotent, and it makes the bootstrap's
      // dependency on the profile explicit rather than incidental.
      PermissionService.instance.update(profile);
    } catch (_) {
      // The dashboard loads the profile itself and falls back.
    }

    try {
      await GeoTrackingService().ensureEnabledIfAllowed();
    } catch (_) {}

    try {
      await FcmWakeHandler.syncTokenWithBackend();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_permissionsOk == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_permissionsOk == false) {
      return PermissionsGateScreen(
        onAllGranted: _onPermissionsGranted,
      );
    }

    final bootstrapFuture = _bootstrapFuture;
    if (bootstrapFuture == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return FutureBuilder<_BootstrapState>(
      future: bootstrapFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return switch (snapshot.data!) {
          _BootstrapState.needsBootstrap => const ServerBootstrapScreen(),
          _BootstrapState.authenticated => const MainShell(),
          _BootstrapState.needsLogin => const LoginScreen(),
        };
      },
    );
  }
}

enum _BootstrapState {
  needsBootstrap,
  needsLogin,
  authenticated,
}
