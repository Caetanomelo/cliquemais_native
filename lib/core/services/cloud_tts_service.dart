import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;

import '../netlify_config.dart';
import 'secure_key_service.dart';
import 'tts_service.dart';

/// Mirrors the source app's `TTSType` routing (cheap/premium/tutor voice).
enum CloudVoiceProfile { standard, premium, tutor }

/// Multi-provider cloud TTS (Google Cloud / ElevenLabs / OpenAI), routed by
/// [CloudVoiceProfile] and falling back to the on-device [TtsService] when
/// no key is configured for the relevant provider. Keys always come from
/// [SecureKeyService] (user-supplied, platform keychain) — never hardcoded,
/// unlike the source app's cleartext-embedded Google key.
///
/// [CloudVoiceProfile.standard] needs no key at all: it goes through the
/// same `/.netlify/functions/tts` Google proxy the web app always uses
/// (shared quota), only preferring a user-supplied Google key when one is
/// set. Premium/tutor profiles (ElevenLabs/OpenAI) still require the
/// user's own key — those were never part of the web app's Netlify proxy.
class CloudTtsService {
  static const _elevenLabsFemaleVoiceId = '21m00Tcm4TlvDq8ikWAM'; // Rachel
  static const _elevenLabsMaleVoiceId = 'TxGEqnHWrfWFTfGW9XjX'; // Josh

  final SecureKeyService _keys;
  final TtsService _fallback;
  final AudioPlayer _player = AudioPlayer();
  final http.Client _client;

  CloudTtsService({
    required SecureKeyService keys,
    required TtsService fallback,
    http.Client? client,
  })  : _keys = keys,
        _fallback = fallback,
        _client = client ?? http.Client();

  Future<void> speak(
    String text, {
    CloudVoiceProfile profile = CloudVoiceProfile.standard,
    double rate = 0.5,
    String voiceGender = 'female',
  }) async {
    if (profile == CloudVoiceProfile.standard) {
      await _speakStandard(text, rate: rate, voiceGender: voiceGender);
      return;
    }
    final provider = profile == CloudVoiceProfile.premium ? ApiProvider.elevenLabs : ApiProvider.openAi;
    final key = await _keys.getKey(provider);
    if (key == null || key.isEmpty) {
      await _fallback.speak(text, rate: rate, voiceGender: voiceGender);
      return;
    }
    try {
      final bytes = await switch (provider) {
        ApiProvider.elevenLabs => _speakElevenLabs(text, key, voiceGender),
        ApiProvider.openAi => _speakOpenAi(text, key, voiceGender),
        ApiProvider.googleTts || ApiProvider.anthropic => throw StateError('unreachable'),
      };
      await _player.stop();
      await _player.play(BytesSource(bytes));
    } catch (_) {
      // Any network/API failure falls back to on-device speech rather than
      // leaving the user with silence.
      await _fallback.speak(text, rate: rate, voiceGender: voiceGender);
    }
  }

  /// [CloudVoiceProfile.standard]: user's own Google key (if set) → shared
  /// Netlify-proxied Google key → on-device, in that order.
  Future<void> _speakStandard(String text, {required double rate, required String voiceGender}) async {
    final userKey = await _keys.getKey(ApiProvider.googleTts);
    try {
      final bytes = (userKey != null && userKey.isNotEmpty)
          ? await _speakGoogle(text, userKey, voiceGender)
          : await _speakGoogleViaNetlify(text, voiceGender);
      await _player.stop();
      await _player.play(BytesSource(bytes));
    } catch (_) {
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

  Future<Uint8List> _speakGoogle(String text, String key, String voiceGender) async {
    final uri = Uri.parse('https://texttospeech.googleapis.com/v1/text:synthesize?key=$key');
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
      throw Exception('Google TTS failed: ${res.statusCode}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return base64Decode(json['audioContent'] as String);
  }

  Future<Uint8List> _speakElevenLabs(String text, String key, String voiceGender) async {
    final voiceId = voiceGender == 'female' ? _elevenLabsFemaleVoiceId : _elevenLabsMaleVoiceId;
    final uri = Uri.parse('https://api.elevenlabs.io/v1/text-to-speech/$voiceId');
    final res = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'xi-api-key': key,
      },
      body: jsonEncode({'text': text, 'model_id': 'eleven_multilingual_v2'}),
    );
    if (res.statusCode != 200) {
      throw Exception('ElevenLabs TTS failed: ${res.statusCode}');
    }
    return res.bodyBytes;
  }

  Future<Uint8List> _speakOpenAi(String text, String key, String voiceGender) async {
    final uri = Uri.parse('https://api.openai.com/v1/audio/speech');
    final res = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $key',
      },
      body: jsonEncode({
        'model': 'tts-1',
        'voice': voiceGender == 'female' ? 'nova' : 'onyx',
        'input': text,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('OpenAI TTS failed: ${res.statusCode}');
    }
    return res.bodyBytes;
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
