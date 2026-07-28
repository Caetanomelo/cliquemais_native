import 'dart:convert';
import 'package:http/http.dart' as http;

import '../netlify_config.dart';

enum AiTutorMode { chat, grammar, vocab, pronunciation }

class AiChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  const AiChatMessage({required this.role, required this.content});
}

/// AI Tutor backend: proxies through `/.netlify/functions/ai-chat` (Gemini,
/// shared key) — same shared-backend pattern as [CloudTtsService]'s standard
/// TTS profile. No user-supplied key involved.
class AiTutorService {
  final http.Client _client;

  AiTutorService({http.Client? client}) : _client = client ?? http.Client();

  Future<String> send({
    required String systemPrompt,
    required List<AiChatMessage> history,
    required String userMessage,
  }) async {
    final uri = Uri.parse('${NetlifyConfig.baseUrl}/.netlify/functions/ai-chat');
    final res = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'systemPrompt': systemPrompt,
        'history': history.map((m) => {'role': m.role, 'content': m.content}).toList(),
        'userMessage': userMessage,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('AI Tutor request failed (${res.statusCode}): ${res.body}');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return json['reply'] as String? ?? '';
  }

  void dispose() => _client.close();
}
