import 'course_language.dart';
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
  // Pre-resolved variants for each of kCourseOverrideLanguages that had an
  // override block in the source JSON. Built once at parse time (which
  // already runs off the UI thread via compute()) so [forLanguage] is a
  // cheap map lookup, not a re-parse, on every screen read.
  final Map<String, Lesson> byLanguage;

  const Lesson({
    required this.type,
    required this.icon,
    required this.name,
    required this.desc,
    required this.content,
    this.byLanguage = const {},
  });

  /// 'en' (the base/default) always returns this lesson unchanged; any other
  /// code falls back to the base lesson if that language has no override
  /// content yet for this particular lesson (matches WEB_BASE's
  /// resolveLessonLanguage: partial/missing es content never blanks a field).
  Lesson forLanguage(String lang) => lang == 'en' ? this : (byLanguage[lang] ?? this);

  static LessonContent _contentFromJson(LessonType type, Map<String, dynamic> j) => switch (type) {
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

  /// Merges an override block (e.g. `j['es']`) onto [base] per lesson type —
  /// vocab remaps each item's `item[code]` onto the `en` field the parsers
  /// expect (see [remapVocabItemLanguage]); convo replaces `dialogues`
  /// wholesale; grammar/practice replace their field(s) when the override
  /// defines them, falling back to the base value otherwise. pronunc/strategy
  /// have no override content in the source data yet, so they fall through
  /// unchanged — adding it later needs no new branch here, just data.
  static LessonContent _resolveOverrideContent(
    LessonType type,
    LessonContent base,
    Map<String, dynamic> override,
    String code,
  ) {
    switch (type) {
      case LessonType.vocab:
        final items = override['items'] as List?;
        if (items == null || base is! VocabLessonContent) return base;
        return VocabLessonContent(
          items.map((e) => VocabItem.fromJson(remapVocabItemLanguage(e as Map<String, dynamic>, code))).toList(),
        );
      case LessonType.convo:
        final dialogues = override['dialogues'];
        if (dialogues == null) return base;
        return ConvoLessonContent(dialoguesFromJson(dialogues));
      case LessonType.grammar:
        if (base is! GrammarLessonContent) return base;
        final rules = override['rules'] as List?;
        return GrammarLessonContent(
          powerLogic: override['power_logic'] as String? ?? base.powerLogic,
          rules: rules != null
              ? rules.map((e) => GrammarRule.fromJson(e as Map<String, dynamic>)).toList()
              : base.rules,
        );
      case LessonType.practice:
        if (base is! PracticeLessonContent) return base;
        final questions = override['questions'] as List?;
        return PracticeLessonContent(
          questions != null
              ? questions.map((e) => PracticeQuestion.fromJson(e as Map<String, dynamic>)).toList()
              : base.questions,
        );
      case LessonType.pronunc:
      case LessonType.strategy:
      case LessonType.unknown:
        return base;
    }
  }

  factory Lesson.fromJson(Map<String, dynamic> j) {
    final type = lessonTypeFromString(j['type'] as String);
    final content = _contentFromJson(type, j);
    final name = j['name'] as String;
    final desc = j['desc'] as String? ?? '';
    final icon = j['icon'] as String? ?? '';

    final byLanguage = <String, Lesson>{};
    for (final code in kCourseOverrideLanguages) {
      final override = j[code] as Map<String, dynamic>?;
      if (override == null) continue;
      byLanguage[code] = Lesson(
        type: type,
        icon: icon,
        name: override['name'] as String? ?? name,
        desc: override['desc'] as String? ?? desc,
        content: _resolveOverrideContent(type, content, override, code),
      );
    }

    return Lesson(type: type, icon: icon, name: name, desc: desc, content: content, byLanguage: byLanguage);
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
