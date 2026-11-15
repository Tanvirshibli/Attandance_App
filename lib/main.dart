import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config/app_config.dart';
import 'config/theme.dart';
import 'services/app_settings_service.dart';
import 'services/device_integrity_service.dart';
import 'services/geo_tracking_service.dart';
import 'services/integrity_lock_service.dart';
import 'services/internet_time_service.dart';
import 'widgets/connectivity_guard.dart';
import 'widgets/integrity_guard.dart';
import 'widgets/location_guard.dart';
import 'widgets/transaction_overlay.dart';
import 'widgets/update_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Local SharedPreferences read (no network), so awaiting it costs one disk
  // read and lets the capture screen pick its language on the first build.
  await AppSettingsService.instance.init();

  // Deliberately not awaited. This does FCM registration, notification channel
  // setup and starts the geo tracking timer — all network and platform work
  // that the first frame does not depend on. Awaiting it here put every one of
  // those behind a cold start on a bad connection, which is most of why the app
  // felt slow to open.
  //
  // AppBootstrap calls ensureEnabledIfAllowed() once permissions are confirmed,
  // so tracking still starts; only the token registration moves later.
  unawaited(_initializeBackgroundServices());

  // Also not awaited: the internet clock is allowed to answer late, and the
  // integrity lock re-covers the app through its notifier when a persisted lock
  // is restored a frame or two after launch.
  unawaited(_initializeIntegrity());

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

Future<void> _initializeIntegrity() async {
  try {
    // Keystore read only — no network — so it lands within a frame or two of
    // the first paint. A device that was locked when the app was closed must be
    // locked again before the employee can reach the punch screen.
    await IntegrityLockService.instance.restore();
  } catch (error) {
    debugPrint('Integrity lock restore failed: $error');
  }

  // Open the clock-watch window with the session, not with the first punch.
  DeviceIntegrityService.instance.startMonitoring();

  // The 15-minute cadence, then the first reading. `sync` coalesces with the
  // timer's own calls and never throws, so neither can break startup.
  InternetTimeService.instance.startAutoResync();
  unawaited(InternetTimeService.instance.sync());
}

class AttendEaseApp extends StatelessWidget {
  const AttendEaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PPHL Attendance System',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // Above the Navigator, so the location check and the offline overlay cover
      // every screen including ones pushed later and survive back navigation.
      //
      // Connectivity sits outside LocationGuard deliberately: when the network is
      // gone the app cannot resolve its location gate either, and an offline
      // overlay that is itself covered by a "location is off" sheet would tell
      // the user to fix the wrong thing. The outer guard wins.
      //
      // The integrity lock is outermost of all three. A device that failed an
      // integrity check must not be able to hide behind a "location is off" or
      // "you are offline" sheet — those are states the user can also create, so
      // ordering the tampering gate last would let it be buried by turning Wi-Fi
      // off.
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        // A transaction barrier covers every route and survives a pop, but it
        // must never cover a tampering or location lock, so it sits inside both.
        final withTransactions = TransactionOverlay(child: content);
        final located = LocationGuard(child: withTransactions);
        final guarded = AppConfig.connectivityGuardEnabled
            ? ConnectivityGuard(child: located)
            : located;
        return IntegrityGuard(child: guarded);
      },
      home: const UpdateGate(),
    );
  }
}