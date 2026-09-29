import 'package:flutter/material.dart';

import '../../config/app_design.dart';
import 'app_header.dart';

/// Standard page frame.
///
/// Every screen repeated the same four lines: a `Scaffold`, a
/// `CustomScrollView`, `AlwaysScrollableScrollPhysics(parent:
/// BouncingScrollPhysics())` and a 20px gutter. The scroll physics matter —
/// dropping `AlwaysScrollable` breaks pull-to-refresh on a short list — so
/// they are baked in here rather than retyped.
///
/// Pass [refresh] only for screens that genuinely support pull-to-refresh;
/// 11 of the 52 do, and the rest must not gain a refresh affordance by
/// accident.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.slivers,
    this.title,
    this.subtitle,
    this.showBack = true,
    this.headerTrailing,
    this.refresh,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.bottomPadding = AppSpace.xl,
    this.background,
  });

  final List<Widget> slivers;

  /// When set, an [AppHeader] is inserted as the first sliver.
  final String? title;
  final String? subtitle;
  final bool showBack;
  final Widget? headerTrailing;

  final Future<void> Function()? refresh;

  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;

  /// Extra clearance at the foot of the list. Leave generous for screens that
  /// host a FAB.
  final double bottomPadding;

  final Color? background;

  @override
  Widget build(BuildContext context) {
    final scrollView = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        if (title != null)
          SliverToBoxAdapter(
            child: AppHeader(
              title: title!,
              subtitle: subtitle,
              showBack: showBack,
              trailing: headerTrailing,
            ),
          ),
        ...slivers,
        SliverToBoxAdapter(child: SizedBox(height: bottomPadding)),
      ],
    );

    return Scaffold(
      backgroundColor: background ?? AppColors.canvas,
      body: refresh == null
          ? scrollView
          : RefreshIndicator(
              onRefresh: refresh!,
              color: AppColors.primary,
              child: scrollView,
            ),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
    );
  }
}
