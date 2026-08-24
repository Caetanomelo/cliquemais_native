import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:http/http.dart' as http;

import 'netlify_post_json.dart';
import 'tts_service.dart';

/// Cloud TTS through the shared `/.netlify/functions/tts` Google proxy (the
/// same backend the web app uses), falling back to the on-device
/// [TtsService] on any network/API failure. No user-supplied key involved.
class CloudTtsService {
  final TtsService _fallback;
  final AudioPlayer _player = AudioPlayer();
  final http.Client _client;

  CloudTtsService({
    required TtsService fallback,
    http.Client? client,
  })  : _fallback = fallback,
        _client = client ?? http.Client();

  /// [language] defaults to English; pass 'pt-BR' to use the Portuguese
  /// voice pair (matches the web app's GOOGLE_TTS_VOICES in tts-shared.js).
  Future<void> speak(
    String text, {
    double rate = 0.5,
    String voiceGender = 'female',
    String language = 'en-US',
  }) async {
    try {
      final bytes = await _speakGoogleViaNetlify(text, voiceGender, language);
      await _player.stop();
      await _player.play(BytesSource(bytes));
    } catch (e, st) {
      // Any network/API failure falls back to on-device speech rather than
      // leaving the user with silence, but still gets recorded so a spike
      // in Netlify/Google TTS failures shows up in Crashlytics.
      unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'CloudTtsService.speak failed', fatal: false));
      await _fallback.speak(text, rate: rate, voiceGender: voiceGender, language: language);
    }
  }

  // Voice names per locale, matching WEB_BASE's tts-shared.js GOOGLE_TTS_VOICES.
  // Adding a new course language's TTS voice is only adding an entry here.
  static const Map<String, ({String male, String female})> _voices = {
    'en-US': (male: 'en-US-Neural2-D', female: 'en-US-Neural2-F'),
    'pt-BR': (male: 'pt-BR-Neural2-B', female: 'pt-BR-Wavenet-A'),
    'es-US': (male: 'es-US-Neural2-B', female: 'es-US-Neural2-A'),
  };

  Future<Uint8List> _speakGoogleViaNetlify(String text, String voiceGender, String language) async {
    final isFemale = voiceGender == 'female';
    final pair = _voices[language] ?? _voices['en-US']!;
    final voiceName = isFemale ? pair.female : pair.male;
    final json = await postJson(
      _client,
      'tts',
      {
        'input': {'text': text},
        'voice': {
          'languageCode': language,
          'name': voiceName,
          'ssmlGender': isFemale ? 'FEMALE' : 'MALE',
        },
        'audioConfig': {'audioEncoding': 'MP3'},
      },
      errorLabel: 'Netlify TTS',
    );
    return base64Decode(json['audioContent'] as String);
  }

  Future<void> stop() async {
    await _player.stop();
    await _fallback.stop();
  }

  void dispose() {
    _player.dispose();
    _client.close();
  }
}
