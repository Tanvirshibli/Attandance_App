import 'package:employee_attendance/models/app_update_manifest.dart';
import 'package:employee_attendance/screens/app_update_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the update screen's layout.
///
/// The screen used to put the changelog, a `Spacer()` and the download button
/// in one `Column`. A Column does not clip its children, it overflows them, so
/// a release note taller than the remaining height pushed the button past the
/// bottom edge where nothing could scroll to it or tap it. On a `force_update`
/// build that button is the only way forward, so the overflow stranded the user
/// on the blocking screen.
///
/// Both of the failure modes below fail on that old layout and pass on the
/// current one: the button finder misses entirely, and the RenderFlex overflow
/// is reported as a test exception.
void main() {
  /// Notes long enough to overflow any handset, and long enough to have
  /// overflowed the old single-Column layout on every screen size.
  final longNotes = List<String>.generate(
    40,
    (i) => 'Release note paragraph $i. This describes a user-visible change '
        'that is long enough to push the layout past the bottom of the screen '
        'and make the download control unreachable.',
  ).join('\n\n');

  AppUpdateManifest manifest({String notes = '', bool force = true}) {
    return AppUpdateManifest.fromJson(<String, dynamic>{
      'app_id': 'com.pphl.employee_attendance',
      'version_name': '2.5.2',
      'version_code': 101,
      'force_update': force,
      'release_notes': notes,
      'published_at': '2026-10-01T14:11:36Z',
      'apks': {
        'arm64-v8a': {
          'url': 'https://example.com/arm64.apk',
          'size_bytes': 49994877,
          'sha256': 'abc',
        },
      },
    });
  }

  /// A short viewport on purpose — the tightest realistic case, and the one that
  /// overflowed first.
  void useShortViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpUpdate(WidgetTester tester, AppUpdateManifest m) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppUpdateScreen(manifest: m, installedVersionCode: 100),
      ),
    );
    await tester.pump();
  }

  group('with a long changelog', () {
    testWidgets('the download button is on screen', (tester) async {
      useShortViewport(tester);
      await pumpUpdate(tester, manifest(notes: longNotes));

      expect(find.text('Download update'), findsOneWidget);
    });

    testWidgets('the download button is tappable', (tester) async {
      useShortViewport(tester);
      await pumpUpdate(tester, manifest(notes: longNotes));

      // Platform.isAndroid is false under flutter test, so a landed tap takes
      // the "Android only" branch. The assertion is that the tap reached the
      // button at all — which it cannot if the button is off-screen.
      await tester.tap(find.text('Download update'));
      await tester.pump();

      expect(find.text('Updates are only supported on Android.'), findsOneWidget);
    });

    testWidgets('the layout does not overflow', (tester) async {
      useShortViewport(tester);
      await pumpUpdate(tester, manifest(notes: longNotes));

      expect(tester.takeException(), isNull);
    });

    testWidgets('the force-update caption stays visible', (tester) async {
      // The caption is the reason the screen cannot be dismissed, so it has to
      // survive a long changelog alongside the button.
      useShortViewport(tester);
      await pumpUpdate(tester, manifest(notes: longNotes, force: true));

      expect(
        find.text('You must install this update to continue using the app.'),
        findsOneWidget,
      );
    });

    testWidgets('the changelog scrolls', (tester) async {
      useShortViewport(tester);
      await pumpUpdate(tester, manifest(notes: longNotes));

      expect(find.byType(SingleChildScrollView), findsOneWidget);

      // Vertical scrolling content, i.e. the changelog rather than a horizontal
      // strip — a wrongly-configured axis would make the notes unreachable on
      // a long release.
      final scrollable = tester.widget<Scrollable>(
        find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        scrollable.axisDirection,
        AxisDirection.down,
        reason: 'release notes must scroll vertically',
      );

      // Dragging moves the content rather than the button: the button is
      // outside the scroll view, so its position is unchanged by the gesture.
      final buttonBefore = tester.getCenter(find.text('Download update'));
      await tester.drag(find.byType(SingleChildScrollView),
          const Offset(0, -200));
      await tester.pump();
      final buttonAfter = tester.getCenter(find.text('Download update'));

      expect(buttonBefore, buttonAfter);
    });
  });

  group('with a short changelog', () {
    testWidgets('the button and caption still render', (tester) async {
      useShortViewport(tester);
      await pumpUpdate(tester, manifest(notes: 'One small note.'));

      expect(find.text('Download update'), findsOneWidget);
      expect(
        find.text('You must install this update to continue using the app.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('no changelog means no notes card', (tester) async {
      useShortViewport(tester);
      await pumpUpdate(tester, manifest(notes: ''));

      expect(find.text('Download update'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a non-forced update omits the caption', (tester) async {
      useShortViewport(tester);
      await pumpUpdate(tester, manifest(notes: longNotes, force: false));

      expect(find.text('Download update'), findsOneWidget);
      expect(
        find.text('You must install this update to continue using the app.'),
        findsNothing,
      );
    });
  });
}
