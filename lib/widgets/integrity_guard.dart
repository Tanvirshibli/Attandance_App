import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../config/app_design.dart';
import '../services/device_identity_service.dart';
import '../services/device_integrity_service.dart';
import '../services/integrity_lock_service.dart';
import '../services/internet_time_service.dart';

/// Covers the whole app while an integrity lock is active.
///
/// Mounted from `MaterialApp.builder`, next to `LocationGuard` and
/// `ConnectivityGuard`, so it sits above the Navigator: no route can be pushed
/// past it, no back gesture can leave it, and a screen written next year is
/// covered without anyone remembering to guard it. That is the same reasoning
/// the other two guards use, and it matters more here — this one exists for
/// people who are actively looking for a way around the app's checks.
///
/// It is not a dialog and it does not wait for the violation to expire. The only
/// way out is [IntegrityLockService.unlockWithPassword]: a real sign-in with the
/// employee's own password. Everything a locked user can spoof from the phone's
/// settings — the mock-location provider, a fake-GPS app, the clock — is
/// available to them right up until the punch is filed, so the gate has to cost
/// something they cannot fabricate.
///
/// The child is kept mounted in slot 0 of the [Stack] rather than swapped for
/// the overlay, exactly as `ConnectivityGuard` does it: replacing the subtree
/// would throw away scroll positions and half-filled forms at the moment the
/// lock lands, and the lock is meant to interrupt the punch, not the typing.
class IntegrityGuard extends StatefulWidget {
  const IntegrityGuard({super.key, required this.child});

  final Widget child;

  @override
  State<IntegrityGuard> createState() => _IntegrityGuardState();
}

class _IntegrityGuardState extends State<IntegrityGuard>
    with WidgetsBindingObserver {
  final IntegrityLockService _lock = IntegrityLockService.instance;

  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  bool _submitting = false;
  bool _obscurePassword = true;
  String? _error;
  String? _deviceIdentifier;
  bool _preparing = false;

  /// How stale internet time may be when the app comes back to the foreground.
  ///
  /// Short, because a phone in a pocket for an hour has been asleep, and
  /// Android's monotonic clock does not count sleep — so the anchor can be an
  /// hour behind real time by the time the employee opens the punch screen. One
  /// round of HEAD requests on resume is cheap next to stamping a punch with an
  /// hour-old clock.
  static const Duration _resumeSyncMaxAge = Duration(seconds: 60);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lock.violation.addListener(_onLockChanged);
    // A lock restored by `IntegrityLockService.restore()` can already be active
    // before this widget is built.
    if (_lock.violation.value != null) {
      unawaited(_prepareLockScreen());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lock.violation.removeListener(_onLockChanged);
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Fire and forget: `syncIfStale` respects its own throttle, shares an
    // in-flight sync and never throws, so a resume on a dead network costs
    // nothing.
    unawaited(
      InternetTimeService.instance.syncIfStale(maxAge: _resumeSyncMaxAge),
    );
  }

  void _onLockChanged() {
    if (_lock.violation.value == null) {
      // Unlocked: drop the credentials rather than leave them in controllers
      // that live for the rest of the process.
      _email.clear();
      _password.clear();
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = null;
        });
      }
      return;
    }
    unawaited(_prepareLockScreen());
  }

  /// Prefills the email the phone already remembers and resolves the device
  /// identifier, so the lock screen names the phone the finding is about.
  ///
  /// Both come from local storage — no network, no spinner — because this screen
  /// can appear the moment the app opens.
  Future<void> _prepareLockScreen() async {
    if (_preparing) return;
    _preparing = true;
    try {
      if (_email.text.isEmpty) {
        final saved = await _lock.savedEmail();
        // The controllers are disposed with this widget, so a late answer must
        // not touch them.
        if (mounted && saved != null && saved.isNotEmpty && _email.text.isEmpty) {
          _email.text = saved;
        }
      }

      if (_deviceIdentifier == null) {
        try {
          final metadata = await DeviceIdentityService().getDeviceMetadata();
          final identifier = metadata['deviceIdentifier'];
          if (mounted && identifier != null && identifier.isNotEmpty) {
            setState(() => _deviceIdentifier = identifier);
          }
        } catch (_) {
          // The identifier is context, not a requirement: the lock works
          // without it.
        }
      }
    } finally {
      _preparing = false;
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final email = _email.text.trim();
    final password = _password.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter the email and password for this account.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    var unlocked = false;
    try {
      unlocked = await _lock.unlockWithPassword(email: email, password: password);
    } catch (error) {
      debugPrint('IntegrityGuard: sign-in threw ($error)');
      unlocked = false;
    }

    if (!mounted) return;

    setState(() {
      _submitting = false;
      // The service returns only success or failure, so the wording stays
      // neutral: it has to be true for a wrong password, a dead network and a
      // slow host alike.
      _error = unlocked
          ? null
          : 'Sign-in failed. Check the password, and the connection, then try '
              'again.';
    });

    if (unlocked) _password.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<IntegrityViolation?>(
      valueListenable: _lock.violation,
      builder: (context, violation, _) {
        final locked = violation != null;

        return PopScope(
          // Not a dialog to be escaped: the overlay *is* the state of the app,
          // and popping would leave the user on a screen that cannot be used.
          canPop: !locked,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Kept mounted and kept in slot 0, so the tree shape does not
              // change when the lock lands (see the class comment).
              IgnorePointer(ignoring: locked, child: widget.child),
              if (violation != null)
                Positioned.fill(child: _overlay(context, violation)),
            ],
          ),
        );
      },
    );
  }

  Widget _overlay(BuildContext context, IntegrityViolation violation) {
    // Colours are resolved explicitly instead of read from the theme's text
    // styles: the app ships a light theme, and this overlay has to stay legible
    // if a dark one is ever added. `ColoredBox` also absorbs hit tests, so a tap
    // on the backdrop cannot reach the app underneath.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.darkSurface : AppColors.surface;
    final ink = isDark ? Colors.white : AppColors.ink;
    final inkMuted = isDark ? Colors.white70 : AppColors.inkMuted;
    final fieldFill = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : AppColors.canvas.withValues(alpha: 0.7);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : AppColors.line;

    return Material(
      type: MaterialType.transparency,
      child: ColoredBox(
        // Opaque, not a scrim: a blur or a translucent sheet would leave the
        // locked app readable and tappable-looking behind it.
        color: const Color(0xFF07100E),
        child: SafeArea(
          child: Padding(
            // Lifts the card above the keyboard. This widget is above the
            // Navigator, so no Scaffold below it resizes for the insets.
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.md,
                  vertical: AppSpace.lg,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.lg,
                      AppSpace.lg,
                      AppSpace.lg,
                      AppSpace.lg,
                    ),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(AppRadius.xxl),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : AppColors.line,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 40,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _badge(),
                            const SizedBox(width: AppSpace.sm),
                            Expanded(
                              child: Text(
                                violation.title,
                                style: AppType.h3.copyWith(
                                  fontSize: 17,
                                  height: 1.3,
                                  letterSpacing: -0.2,
                                  color: ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpace.sm),
                        Text(
                          violation.message,
                          style: AppType.bodySm.copyWith(
                            height: 1.55,
                            color: inkMuted,
                          ),
                        ),
                        const SizedBox(height: AppSpace.md),
                        _howToFix(violation, ink, inkMuted),
                        if (_deviceIdentifier != null) ...[
                          const SizedBox(height: AppSpace.xs),
                          _metaRow(
                            icon: PhosphorIconsRegular.deviceMobile,
                            label: 'Device $_deviceIdentifier',
                            color: inkMuted,
                          ),
                        ],
                        const SizedBox(height: AppSpace.md),
                        Divider(
                          height: 1,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : AppColors.line,
                        ),
                        const SizedBox(height: AppSpace.md),
                        Text(
                          'Sign in to continue',
                          style: AppType.bodyStrong.copyWith(color: ink),
                        ),
                        const SizedBox(height: AppSpace.xxs),
                        Text(
                          'Your password is the only way past this screen. '
                          'Attendance stays blocked on this device until you '
                          'sign in.',
                          style: AppType.micro.copyWith(
                            height: 1.45,
                            color: inkMuted,
                          ),
                        ),
                        const SizedBox(height: AppSpace.sm),
                        _emailField(ink, inkMuted, fieldFill, border),
                        const SizedBox(height: AppSpace.xs),
                        _passwordField(ink, inkMuted, fieldFill, border),
                        if (_error != null) ...[
                          const SizedBox(height: AppSpace.xs),
                          Text(
                            _error!,
                            style: AppType.bodySm.copyWith(
                              color: isDark
                                  ? const Color(0xFFFF8A9B)
                                  : AppColors.error,
                              height: 1.4,
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpace.md),
                        _submitButton(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge() {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: const Center(
        child: PhosphorIcon(
          PhosphorIconsDuotone.shieldWarning,
          size: 22,
          color: AppColors.warning,
          duotoneSecondaryColor: AppColors.warning,
          duotoneSecondaryOpacity: 0.4,
        ),
      ),
    );
  }

  Widget _howToFix(IntegrityViolation violation, Color ink, Color inkMuted) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm,
        vertical: AppSpace.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: PhosphorIcon(
              PhosphorIconsRegular.gear,
              size: 15,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(
              violation.fixHint,
              style: AppType.meta.copyWith(color: ink, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaRow({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      children: [
        PhosphorIcon(icon, size: 14, color: color),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.micro.copyWith(color: color),
          ),
        ),
      ],
    );
  }

  Widget _emailField(Color ink, Color inkMuted, Color fill, Color border) {
    return TextField(
      controller: _email,
      enabled: !_submitting,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.username],
      autocorrect: false,
      style: AppType.body.copyWith(color: ink),
      cursorColor: AppColors.primary,
      decoration: _fieldDecoration(
        hint: 'Work email',
        icon: PhosphorIconsRegular.envelopeSimple,
        ink: ink,
        inkMuted: inkMuted,
        fill: fill,
        border: border,
      ),
    );
  }

  Widget _passwordField(Color ink, Color inkMuted, Color fill, Color border) {
    return TextField(
      controller: _password,
      enabled: !_submitting,
      obscureText: _obscurePassword,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.password],
      autocorrect: false,
      enableSuggestions: false,
      style: AppType.body.copyWith(color: ink),
      cursorColor: AppColors.primary,
      onSubmitted: (_) => _submit(),
      decoration: _fieldDecoration(
        hint: 'Password',
        icon: PhosphorIconsRegular.lockKey,
        ink: ink,
        inkMuted: inkMuted,
        fill: fill,
        border: border,
      ).copyWith(
        suffixIcon: IconButton(
          onPressed: _submitting
              ? null
              : () => setState(() => _obscurePassword = !_obscurePassword),
          icon: PhosphorIcon(
            _obscurePassword
                ? PhosphorIconsRegular.eye
                : PhosphorIconsRegular.eyeSlash,
            size: 17,
            color: inkMuted,
          ),
          tooltip: _obscurePassword ? 'Show password' : 'Hide password',
        ),
      ),
    );
  }

  /// Explicit field colours instead of the app's `inputDecorationTheme`: the
  /// theme fills with [AppColors.surface], which disappears into this card.
  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    required Color ink,
    required Color inkMuted,
    required Color fill,
    required Color border,
  }) {
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: fill,
      hintText: hint,
      hintStyle: AppType.bodySm.copyWith(color: inkMuted),
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: AppSpace.sm, right: AppSpace.xxs),
        child: PhosphorIcon(icon, size: 17, color: inkMuted),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm,
        vertical: AppSpace.sm + 2,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: border),
      ),
    );
  }

  Widget _submitButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _submitting ? null : _submit,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.55),
          disabledForegroundColor: Colors.white70,
          padding: const EdgeInsets.symmetric(vertical: AppSpace.sm + 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        child: _submitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                // Not "Sign in to continue" — that is the heading above the
                // fields, and repeating it as the button label reads as two
                // different actions.
                'Unlock attendance',
                style: AppType.bodyStrong.copyWith(color: Colors.white),
              ),
      ),
    );
  }
}
