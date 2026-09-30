import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/login_screen.dart';
import '../services/auth_service.dart';
import '../services/location_gate_service.dart';
import 'location_required_sheet.dart';

/// Holds the whole app behind a location check.
///
/// Mounted from `MaterialApp.builder`, so it sits above the Navigator and
/// survives every route push — the guard cannot be side-stepped by navigating
/// somewhere that forgets to check, which is what a per-screen check would
/// leave open.
///
/// Re-checked on every resume, not just at launch. Location is a setting the
/// user can change from the app switcher, so a session that started with
/// location on can end up without it; catching that on resume is what keeps a
/// punch from failing at the moment the employee is trying to clock in.
class LocationGuard extends StatefulWidget {
  const LocationGuard({super.key, required this.child});

  final Widget child;

  @override
  State<LocationGuard> createState() => _LocationGuardState();
}

class _LocationGuardState extends State<LocationGuard>
    with WidgetsBindingObserver {
  static const LocationGateService _service = LocationGateService();

  final AuthService _authService = AuthService();

  LocationGateResult? _blocked;

  /// Guards against a second check starting while one is in flight, which would
  /// otherwise queue two sheets after a rapid resume/resume.
  bool _checking = false;

  /// Set once the first check has run, so the guard does not flash its sheet
  /// during the frames before bootstrap has settled.
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Deferred a frame: during initState the login screen may not be mounted
    // yet, and signing out before it exists would navigate to nothing.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_check());
    }
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;

    try {
      // The login screen is reachable without location — there is no punch to
      // record yet, and gating it would strand a user who needs to switch
      // accounts on a device with location off.
      final signedIn = await _authService.isLoggedIn();

      if (!signedIn) {
        if (mounted && (_blocked != null || _initialised)) {
          setState(() {
            _blocked = null;
            _initialised = true;
          });
        } else if (mounted) {
          setState(() => _initialised = true);
        }
        return;
      }

      final result = await _service.check();

      if (!mounted) return;

      setState(() {
        _blocked = result.isBlocking ? result : null;
        _initialised = true;
      });
    } catch (_) {
      // A platform call that throws must not strand the app behind a gate it
      // cannot reason about. Failing open is the safe direction here: the punch
      // path still refuses to record without a fix, and a stuck gate would
      // block a user who cannot do anything about it.
      if (mounted) {
        setState(() {
          _blocked = null;
          _initialised = true;
        });
      }
    } finally {
      _checking = false;
    }
  }

  Future<void> _signOut() async {
    try {
      await _authService.logout();
    } catch (_) {
      // Signing out locally is what actually matters for a locked-out user; a
      // failed server call must not leave them on the gate.
    }

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _blocked;

    if (blocked != null) {
      return LocationRequiredSheet(
        result: blocked,
        onSignOut: _signOut,
        onRecheck: _check,
      );
    }

    return widget.child;
  }
}