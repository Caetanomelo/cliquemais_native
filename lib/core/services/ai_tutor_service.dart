import 'package:http/http.dart' as http;

import 'netlify_post_json.dart';

enum AiTutorMode { chat, pronunciation }

class AiChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  const AiChatMessage({required this.role, required this.content});
}

/// AI Tutor backend: proxies through `/.netlify/functions/ai-chat` (Claude,
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
    final json = await postJson(
      _client,
      'ai-chat',
      {
        'systemPrompt': systemPrompt,
        'history': history.map((m) => {'role': m.role, 'content': m.content}).toList(),
        'userMessage': userMessage,
      },
      errorLabel: 'AI Tutor request',
    );
    return json['reply'] as String? ?? '';
  }

  void dispose() => _client.close();
}
