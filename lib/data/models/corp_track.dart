import 'course_language.dart';
import 'dialogue_line.dart';
import 'vocab_item.dart';

/// One of the 18 orphaned "Corporate Portal" tracks (`CORP_TRACKS` in the
/// source app) — unreachable in the original web app, ported on request.
class CorpTrack {
  final String id;
  final String emoji;
  final String name;
  final String role;
  final String color;
  final String audio;
  final String feedback;
  final List<String> terms;
  final List<VocabItem> vocab;
  final List<List<DialogueLine>> dialogues;
  final Map<String, dynamic> raw;

  const CorpTrack({
    required this.id,
    required this.emoji,
    required this.name,
    required this.role,
    required this.color,
    required this.audio,
    required this.feedback,
    required this.terms,
    required this.vocab,
    required this.dialogues,
    this.raw = const {},
  });

  /// Mirrors WEB_BASE's resolveCorpTrackLanguage(): audio/terms only depend
  /// on the TARGET (via `${target}_content`, target=='en' has no overlay);
  /// feedback follows the same legacy/new-pair split as Lesson, but as a
  /// flat string column (`feedback_${target}_${native}`), not a nested
  /// block.
  CorpTrack forPair(String target, String native) {
    if (target == 'en' && native == 'pt') return this;
    if (target == native) return this;

    final overlay = target == 'es'
        ? raw['es_content'] as Map<String, dynamic>?
        : target == 'pt'
            ? raw['pt_content'] as Map<String, dynamic>?
            : null;
    final newAudio = overlay?['audio'] as String? ?? audio;
    final newTerms = (overlay?['terms'] as List?)?.map((e) => e as String).toList() ?? terms;

    String newFeedback;
    if (native == legacyNative(target)) {
      newFeedback = overlay?['feedback'] as String? ?? feedback;
    } else {
      newFeedback = raw['feedback_${target}_$native'] as String? ?? feedback;
    }

    return CorpTrack(
      id: id,
      emoji: emoji,
      name: name,
      role: role,
      color: color,
      audio: newAudio,
      feedback: newFeedback,
      terms: newTerms,
      vocab: (raw['vocab'] as List? ?? const []).map((e) => VocabItem.forPair(e as Map<String, dynamic>, target, native)).toList(),
      dialogues: dialoguesForPair(raw['dialogues'], target, native),
      raw: raw,
    );
  }

  factory CorpTrack.fromJson(Map<String, dynamic> j) => CorpTrack(
        id: j['id'] as String,
        emoji: j['emoji'] as String? ?? '',
        name: j['name'] as String,
        role: j['role'] as String? ?? '',
        color: j['color'] as String? ?? '#f59e0b',
        audio: j['audio'] as String? ?? '',
        feedback: j['feedback'] as String? ?? '',
        terms: (j['terms'] as List? ?? const []).map((e) => e as String).toList(),
        vocab: (j['vocab'] as List? ?? const []).map((e) => VocabItem.fromJson(e as Map<String, dynamic>)).toList(),
        dialogues: dialoguesFromJson(j['dialogues']),
        raw: j,
      );
}
