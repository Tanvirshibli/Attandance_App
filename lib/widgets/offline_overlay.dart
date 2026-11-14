import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../config/app_design.dart';

/// The blocking screen shown while the app cannot reach the backend.
///
/// Purely presentational: it owns no connectivity state and asks no service
/// anything. `ConnectivityGuard` decides when it belongs on screen, which keeps
/// this widget trivially pumpable in a test and stops a rebuild of the overlay
/// from touching the sampler.
///
/// **The animation carries the screen, not the words.** The centrepiece is a
/// signal cluster — pulse rings expanding from a cloud-slash glyph on a slow
/// orbit — that is several times the size of the headline. Type sits *under* it
/// and stays deliberately small: at arm's length on a phone the moving shape is
/// what the eye lands on, and the sentence only has to confirm what the shape
/// already said. A large headline over a small icon reads as an error dialog; a
/// small caption under a large moving target reads as a state the app is
/// actively working through, which is what this is.
///
/// The blur is applied to what is *behind* the overlay rather than to a scrim
/// colour, so the screen underneath stays recognisable — a user sees their own
/// data dimmed out of reach, not a blank wall that looks like a crash.
///
/// Nothing here animates the blur or any other full-screen effect. Only
/// `transform` and `opacity` move, and every one of them is inside a
/// `RepaintBoundary` no larger than the cluster or the card: a repeating
/// full-surface filter would force the whole screen through the blur engine
/// every frame, which on a mid-range Android phone is visible as stutter.
class OfflineOverlay extends StatefulWidget {
  const OfflineOverlay({super.key});

  @override
  State<OfflineOverlay> createState() => _OfflineOverlayState();
}

class _OfflineOverlayState extends State<OfflineOverlay>
    with TickerProviderStateMixin {
  static const Duration _entryDuration = Duration(milliseconds: 280);

  /// Slow on purpose. Something that pulses quickly reads as an alarm; this is
  /// a wait, so the rings breathe rather than beat.
  static const Duration _pulseDuration = Duration(milliseconds: 2600);
  static const Duration _spinDuration = Duration(milliseconds: 9000);

  /// One-shot arrival: fade, a small scale overshoot and a short rise.
  late final AnimationController _entry;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;

  late final AnimationController _pulse;
  late final AnimationController _spin;

  /// Null until the platform's motion preference has been read.
  bool? _reduceMotion;

  @override
  void initState() {
    super.initState();

    _entry = AnimationController(vsync: this, duration: _entryDuration);
    _fade = CurvedAnimation(parent: _entry, curve: Curves.easeOutCubic);
    // 0.96 -> 1: enough to read as "this arrived" without the bounce that makes
    // a blocking screen feel like a toy.
    _scale = Tween<double>(
      begin: 0.96,
      end: 1,
    ).animate(CurvedAnimation(parent: _entry, curve: Curves.easeOutCubic));
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entry, curve: Curves.easeOutCubic));

    _pulse = AnimationController(vsync: this, duration: _pulseDuration);
    _spin = AnimationController(vsync: this, duration: _spinDuration);

    _entry.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Read on every dependency change, because the platform setting can be
    // toggled while the overlay is up. Reduced motion keeps the one-shot
    // arrival (a fade is not what that setting is about) and drops the two
    // repeating loops, leaving a static ring and a static status dot.
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduceMotion == reduce) return;
    _reduceMotion = reduce;

    if (reduce) {
      _pulse.stop();
      _spin.stop();
    } else {
      if (!_pulse.isAnimating) _pulse.repeat();
      if (!_spin.isAnimating) _spin.repeat();
    }
  }

  @override
  void dispose() {
    _entry.dispose();
    _pulse.dispose();
    _spin.dispose();
    super.dispose();
  }

  bool get _motionReduced => _reduceMotion ?? false;

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
          // First child, so it blurs the screen behind the overlay.
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  // Darker at the edges than the middle: the vignette pushes the
                  // eye toward the card instead of flattening the whole screen
                  // into one grey sheet.
                  gradient: RadialGradient(
                    radius: 0.95,
                    colors: [Color(0xB307100F), Color(0xE60A0E0D)],
                    stops: [0.15, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
              child: FadeTransition(
                opacity: _fade,
                child: ScaleTransition(
                  scale: _scale,
                  child: SlideTransition(
                    position: _slide,
                    child: RepaintBoundary(child: _card()),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card() {
    // A transparent Material has to wrap this card, and not for ink.
    //
    // Flutter's fallback text style when nothing above a `Text` provides a
    // Material is the debug "missing Material" style: a yellow double underline.
    // This overlay is mounted in `MaterialApp.builder`, beside the Navigator
    // rather than inside a route, so unlike every screen (which gets its
    // Material from a Scaffold) it inherits none and every line came out
    // double-underlined. A transparency Material supplies the theme's real text
    // style and paints nothing, so the card's own gradient stays visible.
    return Material(
      type: MaterialType.transparency,
      child: Semantics(
        // A blocking state is worth announcing: a screen-reader user arriving here
        // from a failed action gets no other signal that the app changed.
        liveRegion: true,
        container: true,
        label:
            "Can't connect to the internet. "
            'Check your connection. This screen closes automatically when '
            "you're back online.",
        child: Container(
          constraints: const BoxConstraints(maxWidth: 330),
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.xl,
            AppSpace.lg,
            AppSpace.lg,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF19203A), Color(0xFF0C1222)],
            ),
            borderRadius: BorderRadius.circular(AppRadius.xxl),
            // White at low alpha rather than AppColors.line: this card sits over
            // arbitrary content, and the light-mode border token disappears
            // against a pale screen while a low-alpha white holds its edge on any
            // backdrop.
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
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
            children: [
              _cluster(),
              const SizedBox(height: AppSpace.lg),
              Text(
                "Can't connect to the internet",
                textAlign: TextAlign.center,
                style: AppType.h3.copyWith(
                  fontSize: 17,
                  height: 1.3,
                  letterSpacing: -0.2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                'Check your connection. This screen closes automatically when '
                "you're back online.",
                textAlign: TextAlign.center,
                style: AppType.bodySm.copyWith(
                  height: 1.55,
                  color: Colors.white.withValues(alpha: 0.66),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              _statusPill(),
            ],
          ),
        ),
      ),
    );
  }

  /// The centrepiece: expanding pulse rings around an orbiting mark.
  ///
  /// Sized well above the type on purpose — see the class comment.
  Widget _cluster() {
    return SizedBox(
      width: 176,
      height: 176,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Warm halo, so the mark does not sit on the card as a flat cut-out.
          Container(
            width: 176,
            height: 176,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.accent.withValues(alpha: 0.14),
                  AppColors.accent.withValues(alpha: 0),
                ],
                stops: const [0.25, 0.72],
              ),
            ),
          ),
          if (!_motionReduced) ...[
            _pulseRing(phase: 0),
            _pulseRing(phase: 0.5),
          ],
          _staticRing(),
          _orbitingDot(),
          _disc(),
        ],
      ),
    );
  }

  /// One ring of the outward ripple. Two of them, half a cycle apart, so there
  /// is always one mid-flight and the cluster never looks stalled.
  Widget _pulseRing({required double phase}) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = (_pulse.value + phase) % 1.0;
        final eased = Curves.easeOutCubic.transform(t);
        return Opacity(
          // Fades to nothing as it reaches full size, which is what makes it
          // read as a wave rather than as a growing circle.
          opacity: (1 - t) * 0.42,
          child: Transform.scale(
            scale: 0.66 + eased * 0.72,
            child: Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.7),
                  width: 1.4,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _staticRing() {
    return Container(
      width: 132,
      height: 132,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1.2,
        ),
      ),
    );
  }

  /// A single mark travelling the ring. Cheap (one rotate transform) and it is
  /// what stops the cluster from reading as a still image while the rings are
  /// between beats.
  Widget _orbitingDot() {
    if (_motionReduced) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _spin,
      builder: (context, child) =>
          Transform.rotate(angle: _spin.value * 2 * math.pi, child: child),
      child: SizedBox(
        width: 132,
        height: 132,
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent,
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.55),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _disc() {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF243052), Color(0xFF151D33)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.16),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Center(
        child: PhosphorIcon(
          PhosphorIconsDuotone.cloudSlash,
          size: 42,
          color: Colors.white,
          duotoneSecondaryColor: AppColors.accent,
          duotoneSecondaryOpacity: 0.55,
        ),
      ),
    );
  }

  /// A quiet caption for the wait. Small on purpose: this is the third thing
  /// the eye should reach, after the cluster and the headline.
  Widget _statusPill() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm,
        vertical: AppSpace.xxs + 2,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _statusDot(),
          const SizedBox(width: AppSpace.xs),
          Text(
            'Reconnecting',
            style: AppType.micro.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: Colors.white.withValues(alpha: 0.58),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusDot() {
    if (_motionReduced) {
      return Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.accent.withValues(alpha: 0.75),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        // Breathes between 0.35 and 1 so the pill reads as alive without
        // blinking, which would be distracting at the foot of a blocking screen.
        final t = 0.5 - 0.5 * math.cos(_pulse.value * 2 * math.pi);
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accent.withValues(alpha: 0.35 + t * 0.65),
          ),
        );
      },
    );
  }
}
