import 'package:flutter/material.dart';

import '../services/transaction_ui_service.dart';

/// Paints the blocking transaction overlay above every route.
///
/// Mounted inside `MaterialApp.builder`, below the integrity and location
/// guards: a transaction must never be able to cover a tampering lock, but it
/// must cover screens pushed later, and it must survive the screen that started
/// the work being popped (the punch is submitted after the camera closes).
class TransactionOverlay extends StatelessWidget {
  const TransactionOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TransactionFeedback?>(
      valueListenable: TransactionUiService.instance.feedback,
      builder: (context, feedback, _) {
        if (feedback == null) return child;
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            child,
            Positioned.fill(child: _TransactionBarrier(feedback: feedback)),
          ],
        );
      },
    );
  }
}

class _TransactionBarrier extends StatelessWidget {
  const _TransactionBarrier({required this.feedback});

  final TransactionFeedback feedback;

  static const Color _success = Color(0xFF16A34A);
  static const Color _failure = Color(0xFFDC2626);

  @override
  Widget build(BuildContext context) {
    final status = feedback.status;

    return Semantics(
      liveRegion: true,
      label: switch (status) {
        TransactionStatus.running => feedback.label,
        TransactionStatus.success => '${feedback.label}: done',
        TransactionStatus.failure => '${feedback.label}: failed',
      },
      child: AbsorbPointer(
        absorbing: true,
        child: ColoredBox(
          color: const Color(0xB3000000),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: SizedBox(
                    key: ValueKey<TransactionStatus>(status),
                    width: 148,
                    height: 148,
                    child: switch (status) {
                      TransactionStatus.running => const _ProgressRing(),
                      TransactionStatus.success =>
                        const _OutcomeDisc(color: _success, icon: Icons.check),
                      TransactionStatus.failure =>
                        const _OutcomeDisc(color: _failure, icon: Icons.close),
                    },
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  status == TransactionStatus.running
                      ? feedback.label
                      : (status == TransactionStatus.success
                          ? 'Done'
                          : 'Not completed'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                if (feedback.message != null && feedback.message!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      feedback.message!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.28),
        border: Border.all(color: Colors.white24, width: 2),
      ),
      child: const Padding(
        padding: EdgeInsets.all(14),
        child: CircularProgressIndicator(
          strokeWidth: 7,
          strokeCap: StrokeCap.round,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          backgroundColor: Colors.white12,
        ),
      ),
    );
  }
}

class _OutcomeDisc extends StatelessWidget {
  const _OutcomeDisc({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.16),
        border: Border.all(color: color, width: 6),
      ),
      child: Icon(icon, size: 76, color: color),
    );
  }
}
