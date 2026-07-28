import 'dart:convert';

import '../../core/services/ai_tutor_service.dart' show AiTutorMode;
import '../../core/services/remote_content_service.dart';

/// Loads the AI Tutor's static content (system prompts, quick-suggestion
/// chips, welcome messages) extracted from the source app's `AiTutor`
/// module — one entry per mode (chat/grammar/vocab/pronunciation). Content
/// comes from [RemoteContentService] (Netlify-hosted, cached) with the
/// bundled assets as offline fallback.
class AiContentRepository {
  final RemoteContentService _content;
  AiContentRepository({RemoteContentService? content}) : _content = content ?? RemoteContentService();

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
    final raw = await _content.loadString(asset);
    apply(jsonDecode(raw) as Map<String, dynamic>);
  }

  String systemPromptFor(AiTutorMode mode) => _systemPrompts?[mode.name] ?? '';
  List<String> quickSuggestionsFor(AiTutorMode mode) => _quickSuggestions?[mode.name] ?? const [];
  String welcomeMessageFor(AiTutorMode mode) => _welcomeMessages?[mode.name] ?? '';
}
