import 'dart:convert';

import 'package:http/http.dart' as http;

import '../netlify_config.dart';
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

  /// Streaming counterpart of [send] — mirrors web's `postJSONStream`/
  /// `_callAI(onDelta)` (src/main.js), talking to the same
  /// `ai-chat.mjs` Netlify V2 streaming function so the call screen can
  /// start speaking the first `{{...}}` segment while the rest of the reply
  /// is still generating, instead of waiting for the whole thing. [onDelta]
  /// fires once per text chunk as it arrives; the full concatenated reply
  /// is returned once the stream ends.
  ///
  /// The wire format is newline-delimited JSON, one raw Anthropic
  /// MessageStreamEvent per line. An error that happens *after* streaming
  /// already started can't change the HTTP status anymore, so the backend
  /// signals it with a final `{"type":"error",...}` line instead -- this
  /// throws a plain [Exception] for that case, same as any other failure
  /// here (the call screen's catch-all doesn't distinguish by status).
  Future<String> sendStream({
    required String systemPrompt,
    required List<AiChatMessage> history,
    required String userMessage,
    required void Function(String delta) onDelta,
  }) async {
    final uri = Uri.parse('${NetlifyConfig.baseUrl}/.netlify/functions/ai-chat');
    final req = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      // See netlify_post_json.dart's postJson: checkOrigin() on the backend
      // rejects any request without a matching Origin, which package:http
      // never sends on its own.
      ..headers['Origin'] = NetlifyConfig.baseUrl
      ..body = jsonEncode({
        'systemPrompt': systemPrompt,
        'history': history.map((m) => {'role': m.role, 'content': m.content}).toList(),
        'userMessage': userMessage,
      });

    // Only the initial response (headers) is time-boxed here -- once the
    // stream starts, the body can keep arriving for as long as Claude takes
    // to finish generating.
    final streamed = await _client.send(req).timeout(const Duration(seconds: 20));
    if (streamed.statusCode != 200) {
      final body = await streamed.stream.bytesToString();
      throw Exception('AI Tutor stream request failed (${streamed.statusCode}): $body');
    }

    final full = StringBuffer();
    var lineBuf = '';
    void handleLine(String line) {
      if (line.isEmpty) return;
      Map<String, dynamic> event;
      try {
        event = jsonDecode(line) as Map<String, dynamic>;
      } catch (_) {
        return;
      }
      if (event['type'] == 'error') {
        final err = event['error'] as Map<String, dynamic>? ?? const {};
        throw Exception((err['message'] as String?) ?? 'upstream-error');
      }
      if (event['type'] == 'content_block_delta') {
        final delta = event['delta'] as Map<String, dynamic>?;
        if (delta != null && delta['type'] == 'text_delta') {
          final text = delta['text'] as String? ?? '';
          full.write(text);
          onDelta(text);
        }
      }
    }

    await for (final chunk in streamed.stream.transform(utf8.decoder)) {
      lineBuf += chunk;
      var idx = lineBuf.indexOf('\n');
      while (idx != -1) {
        handleLine(lineBuf.substring(0, idx).trim());
        lineBuf = lineBuf.substring(idx + 1);
        idx = lineBuf.indexOf('\n');
      }
    }
    handleLine(lineBuf.trim());

    return full.toString();
  }

  void dispose() => _client.close();
}
