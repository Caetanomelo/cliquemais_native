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
  // JSON bruto do bloco, retido pra resolucao sob demanda por par
  // (target, native) -- ha ate 6 pares validos por bloco agora, entao
  // pre-computar todos no parse (como antes) so pra 1 idioma nao faz mais
  // sentido; resolve() e um merge barato, chamado raramente (1x por tela).
  final Map<String, dynamic> raw;

  const Lesson({
    required this.type,
    required this.icon,
    required this.name,
    required this.desc,
    required this.content,
    this.raw = const {},
  });

  /// (target='en', native='pt') e o par base, sempre presente sem
  /// resolucao. Outros pares seguem o mesmo algoritmo de
  /// resolveLessonLanguage em src/main.js do WEB_BASE.
  Lesson forPair(String target, String native) {
    if (target == 'en' && native == 'pt') return this;
    if (target == native) return this; // guarda de seguranca, nao deveria acontecer (isValidPair)

    if (type == LessonType.vocab || type == LessonType.convo) {
      return Lesson(
        type: type,
        icon: icon,
        name: name,
        desc: desc,
        content: _contentForPair(type, raw, target, native),
        raw: raw,
      );
    }

    Map<String, dynamic>? override;
    if (native == legacyNative(target)) {
      if (target == 'es') override = raw['es'] as Map<String, dynamic>?;
      if (target == 'pt') override = raw['pt'] as Map<String, dynamic>?;
    } else {
      override = raw['${target}_$native'] as Map<String, dynamic>?;
    }
    if (override == null) return this;

    return Lesson(
      type: type,
      icon: icon,
      name: override['name'] as String? ?? name,
      desc: override['desc'] as String? ?? desc,
      content: _resolveOverrideContent(type, content, override),
      raw: raw,
    );
  }

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

  /// vocab/convo pair-resolved variant: re-picks [target]/[native] per
  /// item/turn straight out of the base JSON's inline triples, instead of
  /// parsing a separate override block.
  static LessonContent _contentForPair(LessonType type, Map<String, dynamic> j, String target, String native) => switch (type) {
        LessonType.vocab => VocabLessonContent(
            (j['items'] as List).map((e) => VocabItem.forPair(e as Map<String, dynamic>, target, native)).toList(),
          ),
        LessonType.convo => ConvoLessonContent(dialoguesForPair(j['dialogues'], target, native)),
        _ => throw ArgumentError('unsupported pair-resolved type: $type'),
      };

  /// vocab/convo blocks store {en,es,pt}/{speaker,en,es,pt} triples inline
  /// (backend migration 038) — a pair variant is just re-picking
  /// [target]/[native] per item/turn from the base JSON, no separate
  /// override object to read. See [_contentForPair].
  ///
  /// Merges an override block (e.g. `raw['es']` or `raw['en_es']`) onto
  /// [base] for the remaining lesson types — grammar/practice replace their
  /// field(s) when the override defines them, falling back to the base
  /// value otherwise. pronunc/strategy have no override content in the
  /// source data yet for most pairs, so they fall through unchanged when the
  /// override (or its `items` field) is missing — adding it later needs no
  /// new branch here, just data.
  static LessonContent _resolveOverrideContent(
    LessonType type,
    LessonContent base,
    Map<String, dynamic> override,
  ) {
    switch (type) {
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
      case LessonType.strategy:
        if (base is! StrategyLessonContent) return base;
        final items = override['items'] as List?;
        return items != null
            ? StrategyLessonContent(items.map((e) => StrategyItem.fromJson(e as Map<String, dynamic>)).toList())
            : base;
      case LessonType.pronunc:
        if (base is! PronuncLessonContent) return base;
        final items = override['items'] as List?;
        return items != null
            ? PronuncLessonContent(items.map((e) => PronuncItem.fromJson(e as Map<String, dynamic>)).toList())
            : base;
      case LessonType.vocab:
      case LessonType.convo:
      case LessonType.unknown:
        return base;
    }
  }

  factory Lesson.fromJson(Map<String, dynamic> j) {
    final type = lessonTypeFromString(j['type'] as String);
    return Lesson(
      type: type,
      icon: j['icon'] as String? ?? '',
      name: j['name'] as String,
      desc: j['desc'] as String? ?? '',
      content: _contentFromJson(type, j),
      raw: j,
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
