import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../config/app_design.dart';

/// The blocking screen shown while the app cannot reach the backend.
///
/// Purely presentational: it owns no connectivity state and asks no service
/// anything. `ConnectivityGuard` decides when it belongs on screen, which keeps
/// this widget trivially pumpable in a test and stops a rebuild of the overlay
/// from touching the sampler.
///
/// The blur is applied to what is *behind* the overlay rather than to a scrim
/// colour, so the screen underneath stays recognisable — a user sees their own
/// data dimmed out of reach, not a blank wall that looks like a crash. That is
/// also why the blur layer is the first child of the [Stack] and the card the
/// second: [BackdropFilter] blurs its backdrop, which is everything painted
/// before it in the same layer.
///
/// Nothing here animates the blur or any other full-screen effect. A repeating
/// full-surface filter forces the whole screen through the blur engine every
/// frame, which on a mid-range Android phone is visible as stutter; the pulse is
/// confined to the icon, where it costs one small transform.
class OfflineOverlay extends StatefulWidget {
  const OfflineOverlay({super.key});

  @override
  State<OfflineOverlay> createState() => _OfflineOverlayState();
}

class _OfflineOverlayState extends State<OfflineOverlay>
    with TickerProviderStateMixin {
  /// Target opacity of the scrim once the overlay has finished fading in.
  static const double _scrimAlpha = 0.55;

  static const Duration _entryDuration = Duration(milliseconds: 250);
  static const Duration _pulseDuration = Duration(milliseconds: 1200);

  /// One-shot fade/slide, so the overlay arrives rather than snapping over the
  /// screen the user is looking at.
  late final AnimationController _entryController;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late final Animation<double> _scrim;

  /// Separate, reversing controller for the icon only.
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();

    _entryController = AnimationController(
      vsync: this,
      duration: _entryDuration,
    );
    _fade = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );
    _scrim = _entryController.drive(Tween<double>(begin: 0, end: _scrimAlpha));
    // A short upward drift: enough to read as "this rose into place" without
    // competing with the fade.
    _slide = Tween<Offset>(begin: const Offset(0, 12), end: Offset.zero)
        .animate(
      CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: _pulseDuration,
    );
    _pulseController.repeat(reverse: true);

    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // AbsorbPointer wraps the whole overlay, not just the scrim, so the screen
    // underneath cannot take a tap even if a caller ever mounts this somewhere
    // that forgets to ignore pointers. The overlay is meant to be the only thing
    // that can receive input while it is up.
    return AbsorbPointer(
      absorbing: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // First child, so it blurs the screen behind the overlay. The scrim
          // rides inside the blur layer rather than under it, which is what puts
          // the tint on top of the blurred backdrop instead of blurring the tint.
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: AnimatedBuilder(
                animation: _scrim,
                builder: (context, _) => Container(
                  color: Colors.black.withValues(alpha: _scrim.value),
                ),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
              child: FadeTransition(
                opacity: _fade,
                child: SlideTransition(
                  position: _slide,
                  child: RepaintBoundary(child: _card()),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 380),
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.lg,
      ),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        // White at low alpha rather than AppColors.line: this card sits over
        // arbitrary content, and the light-mode border token disappears against
        // a pale screen while a low-alpha white holds its edge on any backdrop.
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: AppShadows.floating,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              // 0.94 -> 1.06: readable as a breath rather than a bounce, and
              // small enough that the ring never clips its own bounds.
              final scale = 0.94 + (_pulseController.value * 0.12);
              return Transform.scale(scale: scale, child: child);
            },
            child: _medallion(),
          ),
          const SizedBox(height: AppSpace.md),
          const Text(
            "Can't connect to the internet",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.25,
              letterSpacing: -0.2,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            "Check your connection — this screen will close automatically when "
            "you're back online.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w400,
              height: 1.45,
              color: Colors.white.withValues(alpha: 0.74),
            ),
          ),
        ],
      ),
    );
  }

  Widget _medallion() {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.error.withValues(alpha: 0.14),
        border: Border.all(
          color: AppColors.error.withValues(alpha: 0.45),
          width: 2,
        ),
      ),
      child: const Icon(
        Icons.wifi_off_rounded,
        size: 38,
        color: AppColors.error,
      ),
    );
  }
}
