import 'dart:convert';
import 'dart:math';

import '../../core/services/ai_tutor_service.dart' show AiTutorMode;
import 'json_repository.dart';

/// One Chat/Call persona (Leo or Sofia) for a given native×target pair —
/// mirrors `ai_tutor_personas.json`'s per-key shape from content.js.
class AiPersona {
  final String key;
  final String displayName;
  final String avatar;
  final String prompt;
  final String welcome;

  const AiPersona({
    required this.key,
    required this.displayName,
    required this.avatar,
    required this.prompt,
    required this.welcome,
  });

  factory AiPersona.fromJson(String key, Map<String, dynamic> json) => AiPersona(
        key: key,
        displayName: json['displayName'] as String? ?? '',
        avatar: json['avatar'] as String? ?? '🤖',
        prompt: json['prompt'] as String? ?? '',
        welcome: json['welcome'] as String? ?? '',
      );
}

/// Loads the AI Tutor's content (system prompts, quick-suggestion chips,
/// welcome messages, Leo/Sofia personas) — one entry per mode (chat/pronunciation),
/// plus a standalone 'call' entry used by the voice-call screen (not a tab).
/// Content comes straight from [JsonRepository.content] (Netlify/Supabase-hosted)
/// — no offline fallback.
class AiContentRepository extends JsonRepository {
  AiContentRepository({super.content});

  Map<String, String>? _systemPrompts;
  Map<String, List<String>>? _quickSuggestions;
  Map<String, String>? _welcomeMessages;
  Map<String, AiPersona>? _personas;

  /// [courseLanguage] defaults to 'en' — the same default content.js
  /// applies when `?language=` is absent — so existing callers (tests,
  /// pre-Fase-1 boot order) keep working unchanged. [nativeLanguage] mirrors
  /// content.js's own default (`courseLanguage == 'pt' ? 'en' : 'pt'`) when
  /// omitted — passing it explicitly is what actually picks the right one of
  /// the 6 native×target prompt pairs (ai_tutor_modes, migration 057)
  /// instead of silently falling back to a Portuguese-native prompt for
  /// Spanish-native students.
  Future<void> loadAll([String courseLanguage = 'en', String? nativeLanguage]) async {
    final native = nativeLanguage ?? (courseLanguage == 'pt' ? 'en' : 'pt');
    await Future.wait([
      _load('ai_system_prompts.json', courseLanguage, native, (m) => _systemPrompts = m.map((k, v) => MapEntry(k, v as String))),
      _load(
        'ai_quick_suggestions.json',
        courseLanguage,
        native,
        (m) => _quickSuggestions =
            m.map((k, v) => MapEntry(k, (v as List).map((e) => e as String).toList())),
      ),
      _load('ai_welcome_messages.json', courseLanguage, native, (m) => _welcomeMessages = m.map((k, v) => MapEntry(k, v as String))),
      _load(
        'ai_tutor_personas.json',
        courseLanguage,
        native,
        (m) => _personas = m.map((k, v) => MapEntry(k, AiPersona.fromJson(k, v as Map<String, dynamic>))),
      ),
    ]);
  }

  Future<void> _load(
    String asset,
    String courseLanguage,
    String nativeLanguage,
    void Function(Map<String, dynamic>) apply,
  ) async {
    final raw = await content.loadString(asset, query: {'language': courseLanguage, 'native': nativeLanguage});
    apply(jsonDecode(raw) as Map<String, dynamic>);
  }

  String systemPromptFor(AiTutorMode mode) => systemPromptForKey(mode.name);
  List<String> quickSuggestionsFor(AiTutorMode mode) => _quickSuggestions?[mode.name] ?? const [];
  String welcomeMessageFor(AiTutorMode mode) => welcomeMessageForKey(mode.name);

  /// Raw key lookup for content not backed by an [AiTutorMode] tab — namely
  /// 'call', used by the voice-call screen.
  String systemPromptForKey(String key) => _systemPrompts?[key] ?? '';
  String welcomeMessageForKey(String key) => _welcomeMessages?[key] ?? '';

  /// Randomly picks Leo or Sofia — called once per chat/call screen instance
  /// so the persona stays fixed for that conversation/call's duration (the
  /// caller keeps the returned value in its own state, not this repository).
  /// Falls back to a generic tutor identity if personas failed to load.
  AiPersona pickPersona() {
    final entries = _personas?.values.toList() ?? const <AiPersona>[];
    if (entries.isEmpty) {
      return const AiPersona(key: 'default', displayName: '', avatar: '🤖', prompt: '', welcome: '');
    }
    return entries[Random().nextInt(entries.length)];
  }
}
