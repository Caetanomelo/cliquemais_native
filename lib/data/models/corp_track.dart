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
  // Pre-resolved variants per kCourseOverrideLanguages code that had an
  // override block (`json['${code}_content']`) — same one-time-resolution
  // pattern as Lesson.byLanguage.
  final Map<String, CorpTrack> byLanguage;

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
    this.byLanguage = const {},
  });

  CorpTrack forLanguage(String lang) => lang == 'en' ? this : (byLanguage[lang] ?? this);

  factory CorpTrack.fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String;
    final emoji = j['emoji'] as String? ?? '';
    final name = j['name'] as String;
    final role = j['role'] as String? ?? '';
    final color = j['color'] as String? ?? '#f59e0b';
    final audio = j['audio'] as String? ?? '';
    final feedback = j['feedback'] as String? ?? '';
    final terms = (j['terms'] as List? ?? const []).map((e) => e as String).toList();
    final vocab =
        (j['vocab'] as List? ?? const []).map((e) => VocabItem.fromJson(e as Map<String, dynamic>)).toList();
    final dialogues = dialoguesFromJson(j['dialogues']);

    final byLanguage = <String, CorpTrack>{};
    for (final code in kCourseOverrideLanguages) {
      // vocab/dialogues store {en,es,pt}/{speaker,en,es,pt} triples inline
      // (backend migration 038) — re-pick [code] straight from the base
      // vocab/dialogues instead of a `${code}_content` sub-list, which no
      // longer carries them. `${code}_content` still overrides
      // audio/feedback/terms — those stayed columns of their own.
      final override = j['${code}_content'] as Map<String, dynamic>?;
      byLanguage[code] = CorpTrack(
        id: id,
        emoji: emoji,
        name: name,
        role: role,
        color: color,
        audio: override?['audio'] as String? ?? audio,
        feedback: override?['feedback'] as String? ?? feedback,
        terms: (override?['terms'] as List?)?.map((e) => e as String).toList() ?? terms,
        vocab: (j['vocab'] as List? ?? const [])
            .map((e) => VocabItem.forCode(e as Map<String, dynamic>, code))
            .toList(),
        dialogues: dialoguesForCode(j['dialogues'], code),
      );
    }

    return CorpTrack(
      id: id,
      emoji: emoji,
      name: name,
      role: role,
      color: color,
      audio: audio,
      feedback: feedback,
      terms: terms,
      vocab: vocab,
      dialogues: dialogues,
      byLanguage: byLanguage,
    );
  }
}
