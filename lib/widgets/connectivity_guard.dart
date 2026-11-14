import 'dart:async';

import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';
import 'offline_overlay.dart';

/// Blocks the app behind an offline overlay while the backend is unreachable.
///
/// Mounted high in the tree — above the Navigator, next to `LocationGuard` — so
/// no route can be pushed past it. A per-screen check would leave every screen
/// written after it unprotected, and the screens where a failed request hurts
/// most (a punch, a leave submission) are exactly the ones somebody has to
/// remember to guard.
///
/// Sampling runs only while the app is in the foreground. A periodic TCP probe
/// in the background is a radio wake-up every few seconds: it burns battery,
/// and on Android it is the kind of thing an OEM battery manager shuts down
/// anyway, so the samples become unreliable as well as expensive. The overlay
/// is only ever visible in the foreground, so there is nothing to gain from
/// sampling when it cannot be seen — the app probes once on resume instead.
class ConnectivityGuard extends StatefulWidget {
  const ConnectivityGuard({super.key, required this.child, this.service});

  final Widget child;

  /// Injectable for tests. Defaults to the shared [ConnectivityService.instance].
  final ConnectivityService? service;

  @override
  State<ConnectivityGuard> createState() => _ConnectivityGuardState();
}

class _ConnectivityGuardState extends State<ConnectivityGuard>
    with WidgetsBindingObserver {
  late final ConnectivityService _service;

  /// True when this widget resolved the service itself rather than being handed
  /// one.
  ///
  /// Only [ConnectivityService.stop] is ever called on it, never
  /// [ConnectivityService.dispose]: the singleton outlives every route and is
  /// read elsewhere in the app, so disposing its notifier here would leave those
  /// readers holding a dead [ValueNotifier]. Stopping is enough — it only
  /// cancels the timer, and any later [ConnectivityService.start] re-arms it.
  /// An injected service is left entirely alone, because the caller owns it.
  late final bool _ownsService;

  @override
  void initState() {
    super.initState();

    _ownsService = widget.service == null;
    _service = widget.service ?? ConnectivityService.instance;

    WidgetsBinding.instance.addObserver(this);

    // Deferred to after the first frame: the overlay is driven by the notifier,
    // and changing it during initState could mark a widget dirty that is still
    // being built. Nothing needs an answer before the first frame is on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _service.start();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    if (_ownsService) {
      _service.stop();
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // Both calls, in this order: start() arms the cadence, probeNow() gets
        // an answer without waiting for the first tick. The network can change
        // completely while the app is in the background, so the state carried
        // over from before the pause may already be wrong.
        _service.start();
        unawaited(_service.probeNow());
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // `hidden` is not in the original four states but is delivered on the
        // way to `paused` on newer engines; treating it as "not in the
        // foreground" keeps the sampler off during the transition as well.
        _service.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _service.isOnline,
      builder: (context, online, _) {
        final offline = !online;

        // One tree shape for both states, with the child always in slot 0 and
        // always the same widget instance. Swapping between `child` and a
        // `Stack` would remount the whole subtree at the moment the connection
        // drops — losing scroll position, half-typed text fields and any
        // in-progress form — which is a worse experience than the overlay
        // itself. Only `ignoring` and the overlay's presence change.
        return PopScope(
          // The back button must not dismiss the overlay: it is not a dialog to
          // be escaped, it is the state of the app. Popping would also leave the
          // user on a screen that cannot load anything.
          canPop: !offline,
          child: Stack(
            fit: StackFit.expand,
            children: [
              IgnorePointer(ignoring: offline, child: widget.child),
              if (offline) const Positioned.fill(child: OfflineOverlay()),
            ],
          ),
        );
      },
    );
  }
}
