import 'dialogue_line.dart';
import 'vocab_item.dart';

/// One of the 6 real lesson mechanics found in `UNITS` (source app also has
/// 3 dead types — contrast/portal/mentor_lesson — never rendered, not ported).
sealed class LessonContent {
  const LessonContent();
}

class VocabLessonContent extends LessonContent {
  final List<VocabItem> items;
  const VocabLessonContent(this.items);
}

class ConvoLessonContent extends LessonContent {
  final List<List<DialogueLine>> dialogues;
  const ConvoLessonContent(this.dialogues);
}

class GrammarRow {
  final String sub;
  final String pt;
  const GrammarRow({required this.sub, required this.pt});

  factory GrammarRow.fromJson(Map<String, dynamic> j) => GrammarRow(
        sub: j['sub'] as String,
        pt: j['pt'] as String,
      );
}

class GrammarRule {
  final String label;
  final List<GrammarRow> rows;
  const GrammarRule({required this.label, required this.rows});

  factory GrammarRule.fromJson(Map<String, dynamic> j) => GrammarRule(
        label: j['label'] as String,
        rows: (j['rows'] as List).map((e) => GrammarRow.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class GrammarLessonContent extends LessonContent {
  final String powerLogic;
  final List<GrammarRule> rules;
  const GrammarLessonContent({required this.powerLogic, required this.rules});
}

class PracticeQuestion {
  final String q;
  final List<String> opts;
  final int correct;
  const PracticeQuestion({required this.q, required this.opts, required this.correct});

  factory PracticeQuestion.fromJson(Map<String, dynamic> j) => PracticeQuestion(
        q: j['q'] as String,
        opts: (j['opts'] as List).map((e) => e as String).toList(),
        correct: j['correct'] as int,
      );
}

class PracticeLessonContent extends LessonContent {
  final List<PracticeQuestion> questions;
  const PracticeLessonContent(this.questions);
}

class PronuncItem {
  final String word;
  final String rule;
  final String example;
  const PronuncItem({required this.word, required this.rule, required this.example});

  factory PronuncItem.fromJson(Map<String, dynamic> j) => PronuncItem(
        word: j['word'] as String,
        rule: j['rule'] as String,
        example: j['example'] as String,
      );
}

class PronuncLessonContent extends LessonContent {
  final List<PronuncItem> items;
  const PronuncLessonContent(this.items);
}

class StrategyItem {
  final String phrase;
  final String meaning;
  const StrategyItem({required this.phrase, required this.meaning});

  factory StrategyItem.fromJson(Map<String, dynamic> j) => StrategyItem(
        phrase: j['phrase'] as String,
        meaning: j['meaning'] as String,
      );
}

class StrategyLessonContent extends LessonContent {
  final List<StrategyItem> items;
  const StrategyLessonContent(this.items);
}

/// Content type didn't match a known mechanic (defensive: source data is
/// trusted but this keeps parsing from throwing on future additions).
class UnknownLessonContent extends LessonContent {
  const UnknownLessonContent();
}
