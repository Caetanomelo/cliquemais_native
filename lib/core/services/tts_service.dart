import 'package:flutter_tts/flutter_tts.dart';

/// Wraps flutter_tts for on-device English speech synthesis, replacing the
/// web app's `/.netlify/functions/tts` Google Cloud proxy (unreachable
/// cleanly from native mobile; Phase 1 goes fully offline-capable instead).
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  String _currentLanguage = 'en-US';

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await _tts.setLanguage(_currentLanguage);
    await _tts.awaitSpeakCompletion(true);
    _initialized = true;
  }

  /// [rate] is a 0.0-1.0 fraction matching the source data's `rate` field
  /// (e.g. drive_phrases.json entries), which flutter_tts also expects.
  /// [language] defaults to English; pass 'pt-BR' for the AI Tutor voice call.
  Future<void> speak(String text, {double rate = 0.5, String voiceGender = 'female', String language = 'en-US'}) async {
    await _ensureInit();
    if (language != _currentLanguage) {
      await _tts.setLanguage(language);
      _currentLanguage = language;
    }
    await setVoiceGender(voiceGender, language: language);
    await _tts.setSpeechRate(rate.clamp(0.1, 1.0));
    await _tts.speak(text);
  }

  Future<void> setVoiceGender(String gender, {String language = 'en-US'}) async {
    try {
      final voices = await _tts.getVoices as List?;
      if (voices == null) return;
      final wantFemale = gender == 'female';
      final langPrefix = language.split('-').first;
      for (final v in voices) {
        final map = Map<String, dynamic>.from(v as Map);
        final name = (map['name'] as String? ?? '').toLowerCase();
        final locale = (map['locale'] as String? ?? '');
        if (!locale.startsWith(langPrefix)) continue;
        final isFemale = name.contains('female') || name.contains('f)') || name.contains('woman');
        final isMale = name.contains('male') || name.contains('m)') || name.contains('man');
        if (wantFemale && isFemale) {
          await _tts.setVoice({'name': map['name'], 'locale': locale});
          return;
        }
        if (!wantFemale && isMale) {
          await _tts.setVoice({'name': map['name'], 'locale': locale});
          return;
        }
      }
    } catch (_) {
      // Voice enumeration isn't available on every platform — fall back
      // to the engine's default voice.
    }
  }

  Future<void> stop() => _tts.stop();
}
