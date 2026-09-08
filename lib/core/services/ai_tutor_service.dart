import 'package:http/http.dart' as http;

import 'netlify_post_json.dart';
import 'pronunciation_assessment_service.dart';

enum AiTutorMode { chat, pronunciation }

class AiChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  // Set only for a user turn that came from the mic (pronunciation
  // assessment succeeded) — lets the feed render a score card for that
  // bubble instead of a plain one. Null/empty for every typed turn.
  final double? pronScore;
  final List<PronWord> lowScoreWords;
  // Set only for an assistant turn whose reply carried a
  // [[PRONOUNCE:word or expression]] marker (migration 068) -- already
  // stripped out of [content] by the time this is set. Lets the feed render
  // a "praticar pronúncia" chip below that bubble. Null for every other turn.
  final String? pronounceWord;
  const AiChatMessage({
    required this.role,
    required this.content,
    this.pronScore,
    this.lowScoreWords = const [],
    this.pronounceWord,
  });
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
    final json = await postJson(_client, 'ai-chat', {
      'systemPrompt': systemPrompt,
      'history': history
          .map((m) => {'role': m.role, 'content': m.content})
          .toList(),
      'userMessage': userMessage,
    }, errorLabel: 'AI Tutor request');
    return json['reply'] as String? ?? '';
  }

  void dispose() => _client.close();
}
