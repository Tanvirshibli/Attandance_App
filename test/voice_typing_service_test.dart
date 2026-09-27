import 'package:employee_attendance/services/voice_typing_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = VoiceTypingService();

  group('VoiceLanguage', () {
    test('Bangla offers bn-BD, bn-IN and bare bn as candidates', () {
      expect(
        VoiceLanguage.bangla.localeTags,
        containsAll(<String>['bn-BD', 'bn-IN', 'bn']),
      );
    });

    test('exposes in-vocabulary biasing phrases for both languages', () {
      expect(VoiceLanguage.bangla.phrases, isNotEmpty);
      expect(VoiceLanguage.english.phrases, isNotEmpty);
      // Domain terms are the point of biasing; at least one Bangla-script term
      // must be present or the accuracy fix does nothing for Bangla.
      expect(
        VoiceLanguage.bangla.phrases.any((p) => p.codeUnits.any((c) => c > 0x900)),
        isTrue,
      );
    });

    test('fromName round-trips and defaults to English', () {
      expect(VoiceLanguage.fromName('bangla'), VoiceLanguage.bangla);
      expect(VoiceLanguage.fromName('english'), VoiceLanguage.english);
      expect(VoiceLanguage.fromName('klingon'), VoiceLanguage.english);
      expect(VoiceLanguage.fromName(null), VoiceLanguage.english);
    });
  });

  group('resolveLocale — Bangla', () {
    test('resolves when the device reports bn-BD', () {
      expect(
        service.resolveLocale(
          VoiceLanguage.bangla,
          deviceLocales: <String>['en-US', 'bn-BD'],
        ),
        'bn-BD',
      );
    });

    test('resolves bn-IN when bn-BD is absent', () {
      expect(
        service.resolveLocale(
          VoiceLanguage.bangla,
          deviceLocales: <String>['en-US', 'bn-IN'],
        ),
        'bn-IN',
      );
    });

    test('resolves a bare bn tag', () {
      expect(
        service.resolveLocale(
          VoiceLanguage.bangla,
          deviceLocales: <String>['bn'],
        ),
        'bn',
      );
    });

    test('matches case-insensitively and across the _ / - separator', () {
      expect(
        service.resolveLocale(
          VoiceLanguage.bangla,
          deviceLocales: <String>['BN_bd'],
        ),
        'BN_bd',
      );
    });

    // The original bug: picking বাংলা silently recorded English text because
    // resolveLocale fell back to en_US instead of reporting the gap.
    test('never falls back to English for a Bangla request', () {
      final resolved = service.resolveLocale(
        VoiceLanguage.bangla,
        deviceLocales: <String>['en-US', 'en-GB'],
      );
      expect(resolved, isNull);
      expect(resolved, isNot(startsWith('en')));
    });

    test('returns null on a device with no Bangla support at all', () {
      expect(
        service.resolveLocale(VoiceLanguage.bangla, deviceLocales: <String>[]),
        isNull,
      );
    });
  });

  group('resolveLocale — English', () {
    test('resolves en-US when present', () {
      expect(
        service.resolveLocale(
          VoiceLanguage.english,
          deviceLocales: <String>['en-US', 'bn-BD'],
        ),
        'en-US',
      );
    });

    test('resolves en-GB when en-US is absent', () {
      expect(
        service.resolveLocale(
          VoiceLanguage.english,
          deviceLocales: <String>['bn-BD', 'en-GB'],
        ),
        'en-GB',
      );
    });

    test('returns null when the device has no English either', () {
      expect(
        service.resolveLocale(
          VoiceLanguage.english,
          deviceLocales: <String>['bn-BD'],
        ),
        isNull,
      );
    });
  });

  group('fail-open when the device cannot enumerate languages', () {
    // The native probe returns an empty list when the recognizer cannot be
    // queried. Treating that as "unsupported" made voice typing fail on every
    // phone, because a device with no Bangla pack can still recognise Bangla
    // online. These pin the contract the native path now relies on.

    test('an empty device list is not treated as a hard failure', () {
      // resolveLocale still reports null for a known-empty list; it is the
      // native path that must not treat that null as fatal.
      expect(
        service.resolveLocale(VoiceLanguage.bangla, deviceLocales: <String>[]),
        isNull,
      );
    });

    test('both languages have a usable preferred tag to fail open to', () {
      expect(VoiceLanguage.bangla.localeTags.first, 'bn-BD');
      expect(VoiceLanguage.english.localeTags.first, 'en-US');
    });

    test('the preferred Bangla tag is a valid BCP-47 tag', () {
      expect(
        VoiceLanguage.bangla.localeTags.first,
        matches(RegExp(r'^[a-z]{2}-[A-Z]{2}$')),
      );
    });
  });

  group('failure messages', () {
    test('missing Bangla pack names the offline language pack', () {
      final message = VoiceTypingService.messageFor(
        VoiceFailure.languageUnavailable,
        VoiceLanguage.bangla,
      );
      expect(message, contains('language pack'));
      expect(message, isNot(contains('not available')));
    });

    test('unavailable failure is a generic device message', () {
      final message = VoiceTypingService.messageFor(
        VoiceFailure.unavailable,
        VoiceLanguage.english,
      );
      expect(message, contains('not available'));
    });

    test('no failure produces an empty message', () {
      expect(
        VoiceTypingService.messageFor(VoiceFailure.none, VoiceLanguage.bangla),
        isEmpty,
      );
    });
  });
}
