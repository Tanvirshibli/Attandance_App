import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config/theme.dart';
import 'services/geo_tracking_service.dart';
import 'widgets/location_guard.dart';
import 'widgets/update_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Deliberately not awaited. This does FCM registration, notification channel
  // setup and starts the geo tracking timer — all network and platform work
  // that the first frame does not depend on. Awaiting it here put every one of
  // those behind a cold start on a bad connection, which is most of why the app
  // felt slow to open.
  //
  // AppBootstrap calls ensureEnabledIfAllowed() once permissions are confirmed,
  // so tracking still starts; only the token registration moves later.
  unawaited(_initializeBackgroundServices());

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const AttendEaseApp());
}

Future<void> _initializeBackgroundServices() async {
  try {
    await GeoTrackingService.initialize();
  } catch (error, stack) {
    // Failing here must not stop the app from opening — push registration and
    // tracking are conveniences, and the punch path does not depend on either.
    debugPrint('Background services failed to initialise: $error');
    debugPrintStack(stackTrace: stack);
  }
}

class AttendEaseApp extends StatelessWidget {
  const AttendEaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PPHL Attendance System',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // Above the Navigator, so the location check covers every screen
      // including ones pushed later and survives back navigation.
      builder: (context, child) =>
          LocationGuard(child: child ?? const SizedBox.shrink()),
      home: const UpdateGate(),
    );
  }
}