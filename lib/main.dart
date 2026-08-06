import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config/theme.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'screens/permissions_gate_screen.dart';
import 'screens/server_bootstrap_screen.dart';
import 'services/app_permissions_service.dart';
import 'services/auth_service.dart';
import 'services/endpoint_config_service.dart';
import 'services/face_recognition_service.dart';
import 'services/fcm_wake_handler.dart';
import 'services/geo_tracking_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GeoTrackingService.initialize();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const AttendEaseApp());
}

class AttendEaseApp extends StatelessWidget {
  const AttendEaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PPHL Attendance System',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AppBootstrap(),
    );
  }
}

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
  }

  void _onPermissionsGranted() {
    if (_permissionsOk == true && _bootstrapFuture != null) {
      return;
    }
    setState(() {
      _permissionsOk = true;
      _bootstrapFuture = _prepare();
    });
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

    final profile = await _authService.getCurrentUserProfile();
    _faceRecognitionService.hydrateRegistration(profile?.faceRegistration);
    try {
      await FcmWakeHandler.syncTokenWithBackend();
    } catch (_) {}
    return _BootstrapState.authenticated;
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
