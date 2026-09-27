import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart'
    show SpeechRecognitionResult;

import '../config/app_config.dart';

/// Languages offered in the voice-typing language popup.
enum VoiceLanguage {
  english(
    label: 'English',
    localeTags: ['en-US', 'en_US', 'en-GB', 'en_GB', 'en'],
    phrases: _englishPhrases,
  ),
  bangla(
    label: 'বাংলা',
    localeTags: ['bn-BD', 'bn_BD', 'bn-IN', 'bn_IN', 'bn'],
    phrases: _banglaPhrases,
  );

  const VoiceLanguage({
    required this.label,
    required this.localeTags,
    required this.phrases,
  });

  final String label;

  /// BCP-47 tags tried in order, most specific first. Matching against the
  /// device list by language prefix avoids depending on one exact tag.
  final List<String> localeTags;

  /// In-vocabulary hints biasing the engine toward domain terms. Android's
  /// `EXTRA_SPEECH_INPUT_PHRASES` is the only place these are applied.
  final List<String> phrases;

  String get languageCode => localeTags.first.split('-').first;

  static const _englishPhrases = <String>[
    'broiler',
    'layer',
    'hatcher',
    'feed',
    'fertilizer',
    'vaccine',
    'dealer',
    'party',
    'company',
    'payment',
    'amount',
    'voucher',
    'receipt',
    'kilogram',
    'metric ton',
    'farm',
    'PPSL',
    'Solostar',
  ];

  static const _banglaPhrases = <String>[
    'ব্রয়লার',
    'লেয়ার',
    'হ্যাচার',
    'খাদ্য',
    'সার',
    'ভ্যাকসিন',
    'ডিম',
    'খামার',
    'কৃষক',
    'ডিলার',
    'পার্টি',
    'কোম্পানি',
    'পেমেন্ট',
    'ভাউচার',
    'রশিদ',
    'টাকা',
    'কেজি',
    'মেট্রিক টন',
    'পিপিএসএল',
    'সোলোস্টার',
    'প্রতিষেঠন',
    'চিম ব্যবস্থাপনা',
    'ডিম উৎপাদন',
  ];

  static VoiceLanguage fromName(String? name) {
    return VoiceLanguage.values.firstWhere(
      (l) => l.name == name,
      orElse: () => VoiceLanguage.english,
    );
  }
}

/// Why a dictation session could not run.
enum VoiceFailure {
  none,
  unavailable,
  microphoneDenied,
  languageUnavailable,
  network,
  busy,
  failed,
}

/// Outcome of an attempted dictation session.
class VoiceTypingResult {
  const VoiceTypingResult({
    required this.text,
    required this.isFinal,
    this.failure = VoiceFailure.none,
    this.errorMessage,
  });

  final String text;
  final bool isFinal;
  final VoiceFailure failure;
  final String? errorMessage;

  bool get hasFailure => failure != VoiceFailure.none;
}

/// Dictation for any text field, in English or Bangla.
///
/// On Android this runs through the app's own `VoiceTypingChannel`, which drives
/// `SpeechRecognizer` with biasing phrases, formatting and a silence-restart loop
/// that the `speech_to_text` plugin drops on that platform. Other platforms fall
/// back to `speech_to_text`.
///
/// Only one listening session runs at a time; starting a new one stops the
/// previous.
class VoiceTypingService {
  VoiceTypingService._internal();
  static final VoiceTypingService _instance = VoiceTypingService._internal();
  factory VoiceTypingService() => _instance;

  static const _channel = MethodChannel('com.pphl.employee_attendance/voice_typing');
  static const _languagePref = 'voice_typing_language';
  static const _localePref = 'voice_typing_locale';

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _initialized = false;
  bool _available = false;
  bool _nativeAndroid = false;
  Set<String> _availableLocales = const {};
  VoiceLanguage? _lastLanguage;
  String? _lastLocale;

  bool get isListening => _nativeAndroid ? _nativeListening : _speech.isListening;
  bool get isAvailable => _available;
  bool get isNativePath => _nativeAndroid;

  bool _nativeListening = false;
  MethodChannel? _channelWithHandlers;

  /// Language used for the most recent session, once one has started.
  VoiceLanguage? get lastLanguage => _lastLanguage;

  Future<VoiceLanguage> loadPreferredLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return VoiceLanguage.fromName(prefs.getString(_languagePref));
    } catch (e) {
      debugPrint('VoiceTyping preference read failed: $e');
      return VoiceLanguage.english;
    }
  }

  /// Prepare the recognizer. Returns false when the device has no speech engine
  /// or microphone permission was denied.
  Future<bool> ensureInitialized() async {
    if (_initialized) return _available;
    _initialized = true;
    try {
      if (Platform.isAndroid && await _initNative()) return _available;
      _available = await _initPlugin();
    } catch (e) {
      debugPrint('VoiceTyping init failed: $e');
      _available = false;
    }
    return _available;
  }

  Future<bool> _initNative() async {
    try {
      _channelWithHandlers = _channel;
      _channelWithHandlers!.setMethodCallHandler(_handleNativeCall);
      _available = await _channel.invokeMethod<bool>('isAvailable') ?? false;
      _nativeAndroid = _available;
    } on MissingPluginException {
      // Running on a host without the channel (tests, desktop) — use the plugin.
      _channelWithHandlers = null;
      _nativeAndroid = false;
      _available = false;
    }
    return _available;
  }

  Future<bool> _initPlugin() async {
    _available = await _speech.initialize(
      onError: (error) => debugPrint('VoiceTyping error: ${error.errorMsg}'),
    );
    if (_available) {
      final locales = await _speech.locales();
      _availableLocales = locales.map((l) => l.localeId).toSet();
    }
    return _available;
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'voiceResult':
        final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
        final text = (args['text'] as String? ?? '').trim();
        final isFinal = args['isFinal'] == true;
        if (text.isNotEmpty) {
          _resultSink?.call(VoiceTypingResult(text: text, isFinal: isFinal));
        }
        if (isFinal) {
          _nativeListening = false;
          _doneSink?.call();
        }
      case 'voiceStatus':
        final status = (call.arguments as Map?)?.cast<String, dynamic>();
        if (status?['status'] == 'listening') _nativeListening = true;
        if (status?['status'] == 'done') _nativeListening = false;
      case 'voiceError':
        final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
        final code = args['code'];
        _nativeListening = false;
        _failSink?.call(_mapNativeError(code));
        _doneSink?.call();
    }
  }

  VoiceFailure _mapNativeError(dynamic code) {
    if (code == 1) return VoiceFailure.network;
    if (code == 2) return VoiceFailure.microphoneDenied;
    if (code == 8) return VoiceFailure.busy;
    return VoiceFailure.failed;
  }

  void Function(VoiceTypingResult result)? _resultSink;
  void Function(VoiceFailure failure)? _failSink;
  void Function()? _doneSink;

  /// Locales the device can actually recognise, as locale tags.
  List<String> get availableLocales => _availableLocales.toList();

  /// Last locale actually used to start a session, for diagnostics.
  String? get lastLocale => _lastLocale;

  /// Resolve [language] against what the device supports.
  ///
  /// Returns `null` when the language is unavailable. This deliberately does not
  /// fall back to English: doing so made a Bangla selection silently record
  /// English text, which is worse than an honest "language pack missing".
  String? resolveLocale(VoiceLanguage language, {List<String>? deviceLocales}) {
    final available = (deviceLocales ?? _availableLocales).toList();
    for (final tag in language.localeTags) {
      if (available.contains(tag)) return tag;
    }
    // Fall back to any locale sharing the language prefix, e.g. bn-IN for bn-BD.
    final normalized = <String, String>{};
    for (final tag in available) {
      normalized[_normalize(tag)] = tag;
    }
    for (final tag in language.localeTags) {
      final match = normalized[_normalize(tag)];
      if (match != null) return match;
    }
    return null;
  }

  static String _normalize(String tag) => tag.replaceAll('_', '-').toLowerCase();

  /// Start dictation. [onResult] is called with interim then final text.
  ///
  /// Returns false when speech recognition is unavailable; [onFailure] reports
  /// why, so callers can tell the user something actionable.
  Future<bool> listen({
    required VoiceLanguage language,
    required void Function(VoiceTypingResult result) onResult,
    void Function()? onDone,
    void Function(VoiceFailure failure)? onFailure,
  }) async {
    final ready = await ensureInitialized();
    if (!ready) {
      onFailure?.call(VoiceFailure.unavailable);
      return false;
    }

    if (isListening) {
      await stop();
    }

    _resultSink = onResult;
    _doneSink = onDone;
    _failSink = onFailure;

    if (_nativeAndroid) {
      return _listenNative(language);
    }
    return _listenPlugin(language, onResult, onDone, onFailure);
  }

  Future<bool> _listenNative(
    VoiceLanguage language,
  ) async {
    final locale = await _resolveNativeLocale(language);
    if (locale == null) {
      _failSink?.call(VoiceFailure.languageUnavailable);
      return false;
    }

    await _persistLanguage(language, locale);
    _lastLanguage = language;
    _lastLocale = locale;

    try {
      final started = await _channel.invokeMethod<bool>('listen', {
        'locale': _toBcp47(locale),
        'phrases': language.phrases,
        'pauseMillis': 2500,
        'maxMillis': 180000,
      }) ??
          false;
      if (started) _nativeListening = true;
      return started;
    } on PlatformException catch (e) {
      if (e.code == 'permission_denied') {
        _failSink?.call(VoiceFailure.microphoneDenied);
      } else if (e.code == 'not_available') {
        _failSink?.call(VoiceFailure.unavailable);
      } else {
        _failSink?.call(VoiceFailure.failed);
      }
      return false;
    }
  }

  Future<String?> _resolveNativeLocale(VoiceLanguage language) async {
    final available = await _queryNativeLocales();
    final resolved = resolveLocale(language, deviceLocales: available);
    if (resolved != null) return resolved;
    // No `bn` on device: confirm the engine is not simply reporting only
    // on-device packs while online recognition would still work.
    final prefixMatches = available.any(
      (tag) => _normalize(tag).startsWith(language.languageCode),
    );
    if (prefixMatches) return language.localeTags.first;
    return null;
  }

  Future<List<String>> _queryNativeLocales() async {
    try {
      final tags = await _channel.invokeListMethod<String>('supportedLocales');
      if (tags != null && tags.isNotEmpty) {
        _availableLocales = tags.toSet();
      }
    } on PlatformException {
      // Keep whatever we already know.
    } on MissingPluginException {
      // Not on the native path.
    }
    return _availableLocales.toList();
  }

  String _toBcp47(String tag) => tag.replaceAll('_', '-');

  Future<bool> _listenPlugin(
    VoiceLanguage language,
    void Function(VoiceTypingResult result) onResult,
    void Function()? onDone,
    void Function(VoiceFailure failure)? onFailure,
  ) async {
    final locale = resolveLocale(language);
    if (locale == null) {
      onFailure?.call(VoiceFailure.languageUnavailable);
      return false;
    }

    await _persistLanguage(language, locale);
    _lastLanguage = language;
    _lastLocale = locale;

    await _speech.listen(
      onResult: (result) {
        final best = _bestAlternate(result);
        onResult(
          VoiceTypingResult(text: best, isFinal: result.finalResult),
        );
        if (result.finalResult) onDone?.call();
      },
      listenOptions: stt.SpeechListenOptions(
        cancelOnError: false,
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
        localeId: _toBcp47(locale),
        contextualPhrases: language.phrases,
        listenFor: const Duration(minutes: 3),
        pauseFor: const Duration(seconds: 3),
        autoPunctuation: true,
      ),
    );
    return _speech.isListening;
  }

  /// Prefer the highest-confidence candidate; fall back to the engine's choice.
  String _bestAlternate(SpeechRecognitionResult result) {
    final alternates = result.alternates;
    if (alternates.isEmpty) return result.recognizedWords;
    var best = alternates.first;
    for (final candidate in alternates) {
      if (candidate.confidence > best.confidence) best = candidate;
    }
    return best.recognizedWords;
  }

  Future<void> _persistLanguage(VoiceLanguage language, String locale) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_languagePref, language.name);
      await prefs.setString(_localePref, locale);
    } catch (e) {
      debugPrint('VoiceTyping preference write failed: $e');
    }
  }

  Future<void> stop() async {
    if (_nativeAndroid) {
      try {
        await _channel.invokeMethod<void>('stop');
      } on PlatformException {
        // Already stopped.
      } on MissingPluginException {
        // Nothing to stop.
      }
      _nativeListening = false;
      return;
    }
    if (_speech.isListening) {
      await _speech.stop();
    }
  }

  Future<void> cancel() async {
    if (_nativeAndroid) {
      try {
        await _channel.invokeMethod<void>('cancel');
      } on PlatformException {
        // Already cancelled.
      } on MissingPluginException {
        // Nothing to cancel.
      }
      _nativeListening = false;
      return;
    }
    if (_speech.isListening) {
      await _speech.cancel();
    }
  }

  /// Human-readable guidance for a failure, including how to install a
  /// missing Bangla language pack.
  static String messageFor(VoiceFailure failure, VoiceLanguage language) {
    switch (failure) {
      case VoiceFailure.none:
        return '';
      case VoiceFailure.unavailable:
        return 'Voice typing is not available on this device. '
            'Check microphone permission and internet.';
      case VoiceFailure.microphoneDenied:
        return 'Microphone permission is required for voice typing. '
            'Enable it in Settings → Apps → Permissions.';
      case VoiceFailure.languageUnavailable:
        if (language == VoiceLanguage.bangla) {
          return 'বাংলা voice typing needs the Bangla language pack. '
              'Install it from Google Play Services → Settings → '
              'Download offline speech language, then try again.';
        }
        return 'English voice typing is not available on this device.';
      case VoiceFailure.network:
        return 'Speech recognition needs a connection. '
            'Check your network and try again.';
      case VoiceFailure.busy:
        return 'The microphone is busy with another app. Close it and retry.';
      case VoiceFailure.failed:
        return 'Voice typing stopped unexpectedly. Please try again.';
    }
  }

  /// Intent that opens the offline speech language pack installer, if the
  /// device exposes one. Android-only.
  String? get languagePackInstallerPackage =>
      AppConfig.androidLanguagePackInstaller;
}
