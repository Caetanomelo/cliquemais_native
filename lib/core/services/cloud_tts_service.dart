import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;

import '../netlify_config.dart';
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

  Future<void> speak(
    String text, {
    double rate = 0.5,
    String voiceGender = 'female',
  }) async {
    try {
      final bytes = await _speakGoogleViaNetlify(text, voiceGender);
      await _player.stop();
      await _player.play(BytesSource(bytes));
    } catch (_) {
      // Any network/API failure falls back to on-device speech rather than
      // leaving the user with silence.
      await _fallback.speak(text, rate: rate, voiceGender: voiceGender);
    }
  }

  Future<Uint8List> _speakGoogleViaNetlify(String text, String voiceGender) async {
    final uri = Uri.parse('${NetlifyConfig.baseUrl}/.netlify/functions/tts');
    final res = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'input': {'text': text},
        'voice': {
          'languageCode': 'en-US',
          'ssmlGender': voiceGender == 'female' ? 'FEMALE' : 'MALE',
        },
        'audioConfig': {'audioEncoding': 'MP3'},
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('Netlify TTS failed: ${res.statusCode}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
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
