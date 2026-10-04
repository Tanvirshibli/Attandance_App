import 'package:flutter/material.dart';

/// Gently pulses [child] while [syncing] is true, so the officer can see that
/// the value on screen is still being updated — e.g. a punch that is submitting
/// in the background. Renders the child unchanged, and without a running ticker,
/// once it has settled.
class SyncingTime extends StatefulWidget {
  const SyncingTime({super.key, required this.syncing, required this.child});

  final bool syncing;
  final Widget child;

  @override
  State<SyncingTime> createState() => _SyncingTimeState();
}

class _SyncingTimeState extends State<SyncingTime>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );

  late final Animation<double> _pulse = Tween<double>(
    begin: 0.35,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void initState() {
    super.initState();
    if (widget.syncing) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant SyncingTime oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.syncing && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.syncing && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.syncing) {
      return widget.child;
    }
    return FadeTransition(opacity: _pulse, child: widget.child);
  }
}
