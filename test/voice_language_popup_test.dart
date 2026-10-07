import 'package:employee_attendance/widgets/voice_input_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The mic's language popup is a "pick and start" list, not a radio selection.
/// Re-picking the language already in use must start a session exactly like
/// picking the other one: the old radio-based dialog swallowed that tap
/// (Material radios only report a *change*, so an already-selected radio's tap
/// did nothing) and left the dialog open, which forced the
/// change-language-then-toggle-back dance.
Future<void> _openPopup(WidgetTester tester, TextEditingController controller) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: VoiceTextField(controller: controller)),
    ),
  );
  await tester.pump();
  await tester.tap(find.byIcon(Icons.mic_none_rounded));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('re-picking the current language closes the popup',
      (tester) async {
    final controller = TextEditingController();
    await _openPopup(tester, controller);

    expect(find.text('Voice typing language'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('বাংলা'), findsOneWidget);

    // English is already in effect — this tap used to do nothing at all and
    // left the dialog sitting open.
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(find.text('Voice typing language'), findsNothing);
    // The test host has no speech engine, so the button reports the failure
    // and returns to idle instead of staying stuck in a listening state.
    expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);

    // Let the failure snackbar timers elapse so the test ends with none
    // pending in the fake async zone.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('the popup ticks the language in effect', (tester) async {
    final controller = TextEditingController();
    await _openPopup(tester, controller);

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    // Dismiss by tapping the barrier: no language pops, so nothing attempts to
    // listen and no snackbar timers are created.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Voice typing language'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
