import '../data/models/lesson_content.dart';
import '../data/models/lesson_unit.dart';
import 'services/curriculum_progress_service.dart';
import '../data/repositories/curriculum_repository.dart';
import '../data/repositories/unit_data_repository.dart';

/// Where the learner is in the curriculum: current CEFR level, step within
/// the full sequence, and progress fractions for the Dashboard's level
/// track ("Nível A1 · Passo 2 de 39", "10% para A2").
class JourneyProgress {
  final String cefr;
  final int step;
  final int totalSteps;
  final double overallFraction;
  final double levelFraction;

  const JourneyProgress({
    required this.cefr,
    required this.step,
    required this.totalSteps,
    required this.overallFraction,
    required this.levelFraction,
  });

  static const empty = JourneyProgress(
    cefr: 'A1',
    step: 1,
    totalSteps: 1,
    overallFraction: 0,
    levelFraction: 0,
  );
}

/// Per-domain completion, derived from real lesson-type completion counts
/// (not a separate mastery/scoring system — the app doesn't persist
/// pronunciation/comprehension accuracy yet, so both the radar and the
/// domain-grid share this same curriculum-based figure).
class DomainProgress {
  final double pronuncia;
  final double vocabulario;
  final double fluencia;
  final double compreensao;

  const DomainProgress({
    required this.pronuncia,
    required this.vocabulario,
    required this.fluencia,
    required this.compreensao,
  });

  static const empty = DomainProgress(
    pronuncia: 0,
    vocabulario: 0,
    fluencia: 0,
    compreensao: 0,
  );
}

JourneyProgress computeJourneyProgress(
  CurriculumRepository curriculum,
  CurriculumProgressService progress,
) {
  final units = curriculum.units;
  if (units.isEmpty) return JourneyProgress.empty;

  final steps = <LessonUnit, int>{};
  for (final u in units) {
    steps[u] = curriculum.progressionFor(u.id)?.progression.step ?? u.unit;
  }
  final sorted = units.toList()..sort((a, b) => steps[a]!.compareTo(steps[b]!));
  final totalSteps = steps.values.reduce((a, b) => a > b ? a : b);

  final current = sorted.firstWhere(
    (u) => !progress.isUnitComplete(u.id),
    orElse: () => sorted.last,
  );
  final currentStep = steps[current]!;
  final cefr = curriculum.progressionFor(current.id)?.cefr ?? 'A1';

  final stepsInLevel = sorted
      .where((u) => (curriculum.progressionFor(u.id)?.cefr ?? 'A1') == cefr)
      .map((u) => steps[u]!);
  final minLevelStep = stepsInLevel.reduce((a, b) => a < b ? a : b);
  final maxLevelStep = stepsInLevel.reduce((a, b) => a > b ? a : b);
  final levelSpan = (maxLevelStep - minLevelStep + 1);
  final levelFraction = levelSpan <= 0
      ? 0.0
      : ((currentStep - minLevelStep) / levelSpan).clamp(0.0, 1.0);

  return JourneyProgress(
    cefr: cefr,
    step: currentStep,
    totalSteps: totalSteps,
    overallFraction: (currentStep / totalSteps).clamp(0.0, 1.0),
    levelFraction: levelFraction,
  );
}

DomainProgress computeDomainProgress(
  CurriculumRepository curriculum,
  CurriculumProgressService progress,
) {
  final totals = <LessonType, int>{};
  final done = <LessonType, int>{};
  for (final unit in curriculum.units) {
    for (var i = 0; i < unit.lessons.length; i++) {
      final type = unit.lessons[i].type;
      totals[type] = (totals[type] ?? 0) + 1;
      if (progress.isLessonComplete(unit.id, i)) {
        done[type] = (done[type] ?? 0) + 1;
      }
    }
  }

  double fractionFor(List<LessonType> types) {
    final total = types.fold<int>(0, (sum, t) => sum + (totals[t] ?? 0));
    if (total == 0) return 0;
    final completed = types.fold<int>(0, (sum, t) => sum + (done[t] ?? 0));
    return completed / total;
  }

  return DomainProgress(
    pronuncia: fractionFor([LessonType.pronunc]),
    vocabulario: fractionFor([LessonType.vocab]),
    fluencia: fractionFor([LessonType.practice, LessonType.convo]),
    compreensao: fractionFor([LessonType.grammar, LessonType.strategy]),
  );
}

/// Denominators for the real, per-item Analytics Core (Fase 8): every
/// completable item across the curriculum's 6 lesson types plus Drive Mode
/// phrases and VPC's separate vocab_items table — mirrors WEB_BASE's
/// _computeDomainTotals in index.html. Curriculum `vocab` items and VPC's
/// vocab_items.json are two distinct sets on native (unlike web, where VPC
/// reads the same lessons.json items — see CompletionsService's doc
/// comment), so both are counted into `vocabulary`.
class DomainTotals {
  final int pronunciation;
  final int vocabulary;
  final int fluency;
  final int comprehension;
  const DomainTotals({
    required this.pronunciation,
    required this.vocabulary,
    required this.fluency,
    required this.comprehension,
  });
}

DomainTotals computeDomainTotals(
  CurriculumRepository curriculum,
  UnitDataRepository unitData,
) {
  var pronunciation = 0, vocabulary = 0, fluency = 0, comprehension = 0;
  for (final unit in curriculum.units) {
    for (final lesson in unit.lessons) {
      switch (lesson.content) {
        case VocabLessonContent c:
          vocabulary += c.items.length;
        case GrammarLessonContent c:
          comprehension += c.rules.length;
        case ConvoLessonContent c:
          fluency += c.dialogues.length;
        case PracticeLessonContent c:
          fluency += c.questions.length;
        case PronuncLessonContent c:
          pronunciation += c.items.length;
        case StrategyLessonContent c:
          comprehension += c.items.length;
        case UnknownLessonContent _:
          break;
      }
    }
  }
  for (final u in unitData.drivePhrases) {
    pronunciation += u.phrases.where((p) => p.id != null).length;
  }
  for (final u in unitData.vocabItems) {
    vocabulary += u.items.where((it) => it.id != null).length;
  }
  return DomainTotals(
    pronunciation: pronunciation,
    vocabulary: vocabulary,
    fluency: fluency,
    comprehension: comprehension,
  );
}

/// Real completion counts (from Supabase, keyed like content_completions.domain)
/// against [DomainTotals] denominators -> the same 0..1 fractions
/// [DomainProgress] already uses, so this is a drop-in replacement for
/// [computeDomainProgress] once real counts are available.
DomainProgress domainProgressFromCounts(
  DomainTotals totals,
  Map<String, int> counts,
) {
  double pct(int count, int total) =>
      total == 0 ? 0 : (count / total).clamp(0.0, 1.0);
  return DomainProgress(
    pronuncia: pct(counts['pronunciation'] ?? 0, totals.pronunciation),
    vocabulario: pct(counts['vocabulary'] ?? 0, totals.vocabulary),
    fluencia: pct(counts['fluency'] ?? 0, totals.fluency),
    compreensao: pct(counts['comprehension'] ?? 0, totals.comprehension),
  );
}
