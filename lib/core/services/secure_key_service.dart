import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum ApiProvider { anthropic, elevenLabs, googleTts, openAi }

extension on ApiProvider {
  String get _storageKey => switch (this) {
        ApiProvider.anthropic => 'api_key_anthropic',
        ApiProvider.elevenLabs => 'api_key_elevenlabs',
        ApiProvider.googleTts => 'api_key_google_tts',
        ApiProvider.openAi => 'api_key_openai',
      };
}

/// Stores user-supplied API keys (Anthropic for AI Tutor; ElevenLabs/Google/
/// OpenAI for cloud TTS) in the platform keychain/keystore via
/// flutter_secure_storage — never hardcoded, never in plaintext prefs, unlike
/// the source web app's localStorage-based key storage.
class SecureKeyService {
  final FlutterSecureStorage _storage;

  SecureKeyService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<String?> getKey(ApiProvider provider) => _storage.read(key: provider._storageKey);

  Future<void> setKey(ApiProvider provider, String value) async {
    if (value.trim().isEmpty) {
      await _storage.delete(key: provider._storageKey);
      return;
    }
    await _storage.write(key: provider._storageKey, value: value.trim());
  }

  Future<void> clearKey(ApiProvider provider) => _storage.delete(key: provider._storageKey);

  Future<bool> hasKey(ApiProvider provider) async {
    final v = await getKey(provider);
    return v != null && v.isNotEmpty;
  }
}
