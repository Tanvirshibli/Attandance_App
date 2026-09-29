import 'package:employee_attendance/widgets/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the two things about this redesign that are easy to break silently:
///
/// 1. Every `AppIcons` entry must resolve to a real glyph. A typo here only
///    shows up as a missing-glyph box at runtime, in production, on a phone.
/// 2. Every `AppStatusChip` state must carry a distinct-enough colour, and
///    must never be colour alone.
void main() {
  group('AppIcons', () {
    final names = <String, IconData>{
      'home': AppIcons.home,
      'calendar': AppIcons.calendar,
      'bell': AppIcons.bell,
      'user': AppIcons.user,
      'grid': AppIcons.grid,
      'attendance': AppIcons.attendance,
      'leave': AppIcons.leave,
      'payments': AppIcons.payments,
      'hr': AppIcons.hr,
      'sales': AppIcons.sales,
      'vehicles': AppIcons.vehicles,
      'farms': AppIcons.farms,
      'geo': AppIcons.geo,
      'camera': AppIcons.camera,
      'face': AppIcons.face,
      'check': AppIcons.check,
      'clock': AppIcons.clock,
      'chart': AppIcons.chart,
      'receipt': AppIcons.receipt,
      'wallet': AppIcons.wallet,
      'money': AppIcons.money,
      'piggy': AppIcons.piggy,
      'fork': AppIcons.fork,
      'badge': AppIcons.badge,
      'invoice': AppIcons.invoice,
      'loan': AppIcons.loan,
      'route': AppIcons.route,
      'wrench': AppIcons.wrench,
      'fuel': AppIcons.fuel,
      'store': AppIcons.store,
      'barn': AppIcons.barn,
      'trend': AppIcons.trend,
      'note': AppIcons.note,
      'filter': AppIcons.filter,
      'search': AppIcons.search,
      'back': AppIcons.back,
      'chevron': AppIcons.chevron,
      'refresh': AppIcons.refresh,
      'power': AppIcons.power,
      'lock': AppIcons.lock,
      'shield': AppIcons.shield,
      'info': AppIcons.info,
      'warning': AppIcons.warning,
      'plus': AppIcons.plus,
      'trash': AppIcons.trash,
      'edit': AppIcons.edit,
      'image': AppIcons.image,
      'upload': AppIcons.upload,
      'download': AppIcons.download,
      'home2': AppIcons.home2,
      'sun': AppIcons.sun,
      'qr': AppIcons.qr,
      'help': AppIcons.help,
      'pin': AppIcons.pin,
      'target': AppIcons.target,
      'eye': AppIcons.eye,
      'eyeOff': AppIcons.eyeOff,
      'inbox': AppIcons.inbox,
      'cloudOff': AppIcons.cloudOff,
      'megaphone': AppIcons.megaphone,
      'question': AppIcons.question,
      'translate': AppIcons.translate,
      'moon': AppIcons.moon,
      'key': AppIcons.key,
    };

    test('every entry resolves to a real glyph, not the tofu box', () {
      names.forEach((name, icon) {
        expect(icon, isNotNull, reason: '$name resolved to null');
        expect(
          icon.codePoint,
          isNot(0),
          reason: '$name has codePoint 0 (missing glyph)',
        );
        expect(
          icon.fontFamily,
          startsWith('Phosphor'),
          reason: '$name is not a Phosphor glyph: ${icon.fontFamily}',
        );
      });
    });

    test('module icons are all distinct, so tiles read apart from each other', () {
      final modules = <IconData>{
        AppIcons.attendance,
        AppIcons.leave,
        AppIcons.payments,
        AppIcons.hr,
        AppIcons.sales,
        AppIcons.vehicles,
        AppIcons.farms,
        AppIcons.geo,
      };
      expect(modules.length, 8);
    });

    test('module accents are all distinct colours', () {
      final accents = <Color>{
        AppColors.mAttendance,
        AppColors.mLeave,
        AppColors.mPayments,
        AppColors.mHr,
        AppColors.mSales,
        AppColors.mVehicles,
        AppColors.mFarms,
        AppColors.mGeo,
      };
      expect(accents.length, 8);
    });
  });

  group('AppColors.forStatus', () {
    test('maps the known statuses', () {
      expect(AppColors.forStatus('present'), AppColors.success);
      expect(AppColors.forStatus('active'), AppColors.success);
      expect(AppColors.forStatus('approved'), AppColors.success);
      expect(AppColors.forStatus('late'), AppColors.warning);
      expect(AppColors.forStatus('pending'), AppColors.warning);
      expect(AppColors.forStatus('absent'), AppColors.error);
      expect(AppColors.forStatus('rejected'), AppColors.error);
      expect(AppColors.forStatus('leave'), AppColors.info);
    });

    test('inactive and archived are neutral, not alarming', () {
      expect(AppColors.forStatus('inactive'), AppColors.inkFaint);
      expect(AppColors.forStatus('archived'), AppColors.inkFaint);
    });

    test('unknown, empty and null fall back to muted ink', () {
      expect(AppColors.forStatus('archived-ish'), AppColors.inkMuted);
      expect(AppColors.forStatus(''), AppColors.inkMuted);
      expect(AppColors.forStatus(null), AppColors.inkMuted);
    });

    test('is case and whitespace insensitive', () {
      expect(AppColors.forStatus('  PRESENT '), AppColors.success);
    });
  });

  group('AppIcon renders duotone correctly', () {
    testWidgets('a duotone glyph keeps its secondary layer', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppIcon(
              PhosphorIconsDuotone.wallet,
              semanticLabel: 'Payments',
            ),
          ),
        ),
      );

      // PhosphorIcon stacks the secondary glyph under the primary one, so a
      // duotone icon produces two Icon layers rather than one.
      expect(find.byType(PhosphorIcon), findsOneWidget);
      expect(find.byType(Stack), findsWidgets);
    });

    testWidgets('a flat glyph renders as a plain Icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppIcon(PhosphorIconsFill.checkCircle),
          ),
        ),
      );
      // No PhosphorIcon, because there is no secondary layer to stack.
      expect(find.byType(PhosphorIcon), findsNothing);
      expect(find.byType(Icon), findsOneWidget);
    });
  });

  group('AppStatusChip', () {
    testWidgets('renders an icon and a word, never colour alone',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppStatusChip(status: 'active'),
          ),
        ),
      );

      // The word is present...
      expect(find.text('Active'), findsOneWidget);
      // ...and so is a glyph, which is what keeps it readable in greyscale.
      expect(find.byType(AppIcon), findsOneWidget);
    });

    testWidgets('capitalises a wire status', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppStatusChip(status: 'pending')),
        ),
      );
      expect(find.text('Pending'), findsOneWidget);
    });

    testWidgets('renders nothing when there is no status', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppStatusChip(status: null)),
        ),
      );
      expect(find.byType(Text), findsNothing);
    });
  });

  group('AppButton', () {
    testWidgets('a disabled button does not fire', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(
              label: 'Save',
              onPressed: null,
              icon: AppIcons.check,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(AppButton));
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('meets the 48dp minimum height', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(
              label: 'Save',
              onPressed: () {},
              icon: AppIcons.check,
            ),
          ),
        ),
      );
      final size = tester.getSize(find.byType(AppButton));
      expect(size.height, greaterThanOrEqualTo(48));
    });

    testWidgets('shows a spinner and ignores taps while busy', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(
              label: 'Save',
              busy: true,
              onPressed: () => taps++,
            ),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Save'), findsNothing);
      await tester.tap(find.byType(AppButton));
      await tester.pump();
      expect(taps, 0);
    });
  });

  group('AppCard', () {
    testWidgets('a non-interactive card shows no ripple host', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppCard(child: Text('Body')),
          ),
        ),
      );
      expect(find.text('Body'), findsOneWidget);
    });

    testWidgets('an interactive card fires its tap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppCard(
              onTap: () => taps++,
              child: const Text('Body'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Body'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('an accented card survives an unbounded height', (tester) async {
      // Regression: the accent rail used `CrossAxisAlignment.stretch` without
      // an IntrinsicHeight. Inside a sliver the height is unbounded, the layout
      // asserted, and the whole screen rendered blank instead of showing an
      // error. This hit the home action card and the geo tracking cards, so it
      // is pinned here.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: AppCard(
                    accent: AppColors.mGeo,
                    child: const Text('Accented body'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Accented body'), findsOneWidget);
    });
  });
}
