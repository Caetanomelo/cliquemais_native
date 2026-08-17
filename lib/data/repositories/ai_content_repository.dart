import 'dart:convert';

import '../../core/services/ai_tutor_service.dart' show AiTutorMode;
import 'json_repository.dart';

/// Loads the AI Tutor's content (system prompts, quick-suggestion chips,
/// welcome messages) — one entry per mode (chat/pronunciation), plus a
/// standalone 'call' entry used by the voice-call screen (not a tab).
/// Content comes straight from [JsonRepository.content] (Netlify/Supabase-hosted)
/// — no offline fallback.
class AiContentRepository extends JsonRepository {
  AiContentRepository({super.content});

  Map<String, String>? _systemPrompts;
  Map<String, List<String>>? _quickSuggestions;
  Map<String, String>? _welcomeMessages;

  Future<void> loadAll() async {
    await Future.wait([
      _load('ai_system_prompts.json', (m) => _systemPrompts = m.map((k, v) => MapEntry(k, v as String))),
      _load(
        'ai_quick_suggestions.json',
        (m) => _quickSuggestions =
            m.map((k, v) => MapEntry(k, (v as List).map((e) => e as String).toList())),
      ),
      _load('ai_welcome_messages.json', (m) => _welcomeMessages = m.map((k, v) => MapEntry(k, v as String))),
    ]);
  }

  Future<void> _load(String asset, void Function(Map<String, dynamic>) apply) async {
    final raw = await content.loadString(asset);
    apply(jsonDecode(raw) as Map<String, dynamic>);
  }

  String systemPromptFor(AiTutorMode mode) => systemPromptForKey(mode.name);
  List<String> quickSuggestionsFor(AiTutorMode mode) => _quickSuggestions?[mode.name] ?? const [];
  String welcomeMessageFor(AiTutorMode mode) => welcomeMessageForKey(mode.name);

  /// Raw key lookup for content not backed by an [AiTutorMode] tab — namely
  /// 'call', used by the voice-call screen.
  String systemPromptForKey(String key) => _systemPrompts?[key] ?? '';
  String welcomeMessageForKey(String key) => _welcomeMessages?[key] ?? '';
}
