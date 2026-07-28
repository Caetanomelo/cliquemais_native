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
  });

  factory CorpTrack.fromJson(Map<String, dynamic> j) => CorpTrack(
        id: j['id'] as String,
        emoji: j['emoji'] as String? ?? '',
        name: j['name'] as String,
        role: j['role'] as String? ?? '',
        color: j['color'] as String? ?? '#f59e0b',
        audio: j['audio'] as String? ?? '',
        feedback: j['feedback'] as String? ?? '',
        terms: (j['terms'] as List? ?? const []).map((e) => e as String).toList(),
        vocab: (j['vocab'] as List? ?? const [])
            .map((e) => VocabItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        dialogues: dialoguesFromJson(j['dialogues']),
      );
}
