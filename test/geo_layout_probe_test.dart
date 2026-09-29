import 'package:employee_attendance/widgets/ui/ui.dart';
import 'package:employee_attendance/widgets/gradient_screen_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reproduces the geo tracking scroll body in isolation.
///
/// Geo tracking renders blank on device, and the whole screen goes with it —
/// which is the signature of a layout assertion inside a sliver rather than a
/// data problem. `LiveLocationMap` cannot be pumped here (it needs a real
/// Google Map), so the panel is swapped for a fixed-height box and everything
/// around it is the real code path.
///
/// If this test throws, the offending line is identified in seconds instead of
/// one build-install-screenshot cycle.
void main() {
  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  testWidgets('geo scroll body lays out inside a sliver', (tester) async {
    usePhoneViewport(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: AppColors.canvas,
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(
                child: AppHeader(
                  title: 'Geo tracking',
                  subtitle: 'Live map · every 5 min',
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.gutter,
                  AppSpace.xs,
                  AppSpace.gutter,
                  AppSpace.xl,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Stands in for LiveLocationMap, which needs a platform map.
                    const SizedBox(height: 300),
                    const SizedBox(height: AppSpace.md),
                    _trackingCard(),
                    const SizedBox(height: AppSpace.sm),
                    _statusChips(),
                    const SizedBox(height: AppSpace.md),
                    _actionRow(),
                    const SizedBox(height: AppSpace.xs),
                    _historySection(),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
  });

  testWidgets('a gradient header still lays out beside the new one',
      (tester) async {
    usePhoneViewport(tester);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: GradientScreenHeader(
                  title: 'Geo Tracking',
                  subtitle: 'Live map · every 5 min',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

Widget _trackingCard() {
  final accent = AppColors.mGeo;
  return AppCard(
    padding: const EdgeInsets.all(AppSpace.md),
    child: Row(
      children: [
        AppIconTile(
          icon: AppIcons.geo,
          color: accent,
          size: AppIconTileSize.large,
          filled: true,
          semanticLabel: 'Tracking on',
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Tracking on',
                style: AppType.h3.copyWith(color: AppColors.ink),
              ),
              const SizedBox(height: 2),
              Text(
                'Background location granted',
                style: AppType.meta.copyWith(color: AppColors.inkMuted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _statusChips() {
  const chips = <(IconData, String)>[
    (PhosphorIconsDuotone.clock, 'Every 5 min'),
    (PhosphorIconsDuotone.upload, '3 pending'),
    (PhosphorIconsDuotone.batteryCharging, 'WorkManager'),
    (PhosphorIconsDuotone.bell, 'FCM ready'),
  ];
  return Wrap(
    spacing: AppSpace.xs,
    runSpacing: AppSpace.xs,
    children: chips.map((chip) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm,
          vertical: AppSpace.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(chip.$1, size: 14, color: AppColors.mGeo),
            const SizedBox(width: AppSpace.xxs + 2),
            Text(
              chip.$2,
              style: AppType.micro.copyWith(color: AppColors.inkMuted),
            ),
          ],
        ),
      );
    }).toList(),
  );
}

Widget _actionRow() {
  return AppButton(
    label: 'Capture now',
    icon: AppIcons.target,
    accent: AppColors.mGeo,
    onPressed: () {},
  );
}

Widget _historySection() {
  return AppCard(
    padding: const EdgeInsets.all(AppSpace.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            AppSectionTitle(title: 'Recent pings', accent: AppColors.mGeo),
            Spacer(),
            Text(
              '02:02 PM',
              style: TextStyle(fontSize: 11, color: AppColors.inkFaint),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        const Text(
          'No history yet. Capture a ping or enable tracking.',
          style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
        ),
      ],
    ),
  );
}
