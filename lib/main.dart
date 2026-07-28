import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config/theme.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'screens/server_bootstrap_screen.dart';
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

class _AppBootstrapState extends State<AppBootstrap> {
  final AuthService _authService = AuthService();
  final FaceRecognitionService _faceRecognitionService = FaceRecognitionService();
  final EndpointConfigService _configService = EndpointConfigService.instance;
  late Future<_BootstrapState> _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = _prepare();
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
    return FutureBuilder<_BootstrapState>(
      future: _bootstrapFuture,
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
