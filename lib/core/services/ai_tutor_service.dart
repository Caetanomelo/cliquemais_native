import 'dart:convert';
import 'package:http/http.dart' as http;

import 'secure_key_service.dart';

enum AiTutorMode { chat, grammar, vocab, pronunciation }

class AiChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  const AiChatMessage({required this.role, required this.content});
}

/// Thrown when no Anthropic key is configured yet — callers should prompt
/// the user to add one in Settings rather than surface a raw HTTP error.
class AiTutorNoKeyException implements Exception {}

/// Real Anthropic Messages API integration for the AI Tutor. Fixes the
/// source app's bug of shipping the fetch() call with no auth headers at
/// all (always failed as shipped) — this sends both `x-api-key` and the
/// required `anthropic-version` header, using the key the user configured
/// in Settings via [SecureKeyService] (never hardcoded).
class AiTutorService {
  static const _model = 'claude-sonnet-5';
  static const _apiVersion = '2023-06-01';
  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _maxTokens = 1024;

  final SecureKeyService _keys;
  final http.Client _client;

  AiTutorService({required SecureKeyService keys, http.Client? client})
      : _keys = keys,
        _client = client ?? http.Client();

  Future<bool> hasApiKey() => _keys.hasKey(ApiProvider.anthropic);

  Future<String> send({
    required String systemPrompt,
    required List<AiChatMessage> history,
    required String userMessage,
  }) async {
    final key = await _keys.getKey(ApiProvider.anthropic);
    if (key == null || key.isEmpty) {
      throw AiTutorNoKeyException();
    }
    final res = await _client.post(
      Uri.parse(_endpoint),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': key,
        'anthropic-version': _apiVersion,
      },
      body: jsonEncode({
        'model': _model,
        'max_tokens': _maxTokens,
        'system': systemPrompt,
        'messages': [
          ...history.map((m) => {'role': m.role, 'content': m.content}),
          {'role': 'user', 'content': userMessage},
        ],
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('AI Tutor request failed (${res.statusCode}): ${res.body}');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final blocks = json['content'] as List;
    return blocks.map((b) => (b as Map<String, dynamic>)['text'] as String? ?? '').join();
  }

  void dispose() => _client.close();
}
