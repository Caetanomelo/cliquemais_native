import 'dialogue_line.dart';
import 'lesson_content.dart';
import 'vocab_item.dart';

enum LessonType { vocab, convo, grammar, practice, pronunc, strategy, unknown }

LessonType lessonTypeFromString(String s) => switch (s) {
      'vocab' => LessonType.vocab,
      'convo' => LessonType.convo,
      'grammar' => LessonType.grammar,
      'practice' => LessonType.practice,
      'pronunc' => LessonType.pronunc,
      'strategy' => LessonType.strategy,
      _ => LessonType.unknown,
    };

class Lesson {
  final LessonType type;
  final String icon;
  final String name;
  final String desc;
  final LessonContent content;

  const Lesson({
    required this.type,
    required this.icon,
    required this.name,
    required this.desc,
    required this.content,
  });

  factory Lesson.fromJson(Map<String, dynamic> j) {
    final type = lessonTypeFromString(j['type'] as String);
    final LessonContent content = switch (type) {
      LessonType.vocab => VocabLessonContent(
          (j['items'] as List).map((e) => VocabItem.fromJson(e as Map<String, dynamic>)).toList(),
        ),
      LessonType.convo => ConvoLessonContent(dialoguesFromJson(j['dialogues'])),
      LessonType.grammar => GrammarLessonContent(
          powerLogic: j['power_logic'] as String? ?? '',
          rules: (j['rules'] as List).map((e) => GrammarRule.fromJson(e as Map<String, dynamic>)).toList(),
        ),
      LessonType.practice => PracticeLessonContent(
          (j['questions'] as List).map((e) => PracticeQuestion.fromJson(e as Map<String, dynamic>)).toList(),
        ),
      LessonType.pronunc => PronuncLessonContent(
          (j['items'] as List).map((e) => PronuncItem.fromJson(e as Map<String, dynamic>)).toList(),
        ),
      LessonType.strategy => StrategyLessonContent(
          (j['items'] as List).map((e) => StrategyItem.fromJson(e as Map<String, dynamic>)).toList(),
        ),
      LessonType.unknown => const UnknownLessonContent(),
    };
    return Lesson(
      type: type,
      icon: j['icon'] as String? ?? '',
      name: j['name'] as String,
      desc: j['desc'] as String? ?? '',
      content: content,
    );
  }
}

class LessonUnit {
  final String id;
  final int unit;
  final String title;
  final String subtitle;
  final String book;
  final List<String> goals;
  final List<Lesson> lessons;

  const LessonUnit({
    required this.id,
    required this.unit,
    required this.title,
    required this.subtitle,
    required this.book,
    required this.goals,
    required this.lessons,
  });

  factory LessonUnit.fromJson(String id, Map<String, dynamic> j) => LessonUnit(
        id: id,
        unit: int.parse(id.replaceFirst('unit', '')),
        title: j['title'] as String,
        subtitle: j['subtitle'] as String? ?? '',
        book: j['book'] as String? ?? '',
        goals: (j['goals'] as List? ?? const []).map((e) => e as String).toList(),
        lessons: (j['lessons'] as List).map((e) => Lesson.fromJson(e as Map<String, dynamic>)).toList(),
      );
}
