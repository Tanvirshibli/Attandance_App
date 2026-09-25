import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Languages offered in the voice-typing language popup.
enum VoiceLanguage {
  english('en_US', 'English'),
  bangla('bn_BD', 'বাংলা');

  const VoiceLanguage(this.localeId, this.label);
  final String localeId;
  final String label;
}

/// Result of a completed/failed dictation session.
class VoiceTypingResult {
  const VoiceTypingResult({
    required this.text,
    required this.isFinal,
    this.errorMessage,
  });

  final String text;
  final bool isFinal;
  final String? errorMessage;
}

/// Wraps `speech_to_text` so widgets can dictate English or Bangla into any
/// text field. Only one listening session runs at a time; a new session stops
/// the previous one.
class VoiceTypingService {
  VoiceTypingService._internal();
  static final VoiceTypingService _instance = VoiceTypingService._internal();
  factory VoiceTypingService() => _instance;

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _initialized = false;
  bool _available = false;
  Set<String> _availableLocales = const {};

  bool get isListening => _speech.isListening;
  bool get isAvailable => _available;

  /// Prepare the plugin. Returns false when the device has no speech engine
  /// or microphone permission was denied.
  Future<bool> ensureInitialized() async {
    if (_initialized) return _available;
    _initialized = true;
    try {
      _available = await _speech.initialize(
        onError: (error) =>
            debugPrint('VoiceTyping error: ${error.errorMsg}'),
      );
      if (_available) {
        final locales = await _speech.locales();
        _availableLocales = locales.map((l) => l.localeId).toSet();
      }
    } catch (e) {
      debugPrint('VoiceTyping init failed: $e');
      _available = false;
    }
    return _available;
  }

  /// Resolve the requested locale; fall back to a similar locale on the
  /// device (e.g. bn_IN for Bangla) and finally to English.
  String resolveLocale(VoiceLanguage language) {
    if (_availableLocales.contains(language.localeId)) {
      return language.localeId;
    }
    final prefix = language.localeId.split('_').first;
    final similar = _availableLocales.where((l) => l.startsWith(prefix));
    if (similar.isNotEmpty) return similar.first;
    return VoiceLanguage.english.localeId;
  }

  /// Start dictation. [onResult] is called with interim then final text.
  /// Returns false when speech recognition is unavailable.
  Future<bool> listen({
    required VoiceLanguage language,
    required void Function(VoiceTypingResult result) onResult,
    void Function()? onDone,
  }) async {
    final ready = await ensureInitialized();
    if (!ready) return false;

    if (_speech.isListening) {
      await _speech.stop();
    }

    await _speech.listen(
      onResult: (result) {
        onResult(
          VoiceTypingResult(
            text: result.recognizedWords,
            isFinal: result.finalResult,
          ),
        );
        if (result.finalResult) onDone?.call();
      },
      listenOptions: stt.SpeechListenOptions(
        cancelOnError: true,
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
        localeId: resolveLocale(language),
        listenFor: const Duration(minutes: 2),
        pauseFor: const Duration(seconds: 4),
      ),
    );
    return _speech.isListening;
  }

  Future<void> stop() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
  }

  Future<void> cancel() async {
    if (_speech.isListening) {
      await _speech.cancel();
    }
  }
}
