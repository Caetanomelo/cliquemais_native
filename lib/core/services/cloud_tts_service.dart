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

  Future<Uint8List> _speakGoogleViaNetlify(String text, String voiceGender, String language) async {
    final isFemale = voiceGender == 'female';
    final voiceName = language == 'pt-BR'
        ? (isFemale ? 'pt-BR-Wavenet-A' : 'pt-BR-Neural2-B')
        : (isFemale ? 'en-US-Neural2-F' : 'en-US-Neural2-D');
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
