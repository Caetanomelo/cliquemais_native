List<String> _strList(dynamic v) => (v as List? ?? const []).map((e) => e as String).toList();

/// The "I can..." statements shown on completion (CanDoCard / MilestoneCelebration).
class CanDoStatements {
  final List<String> spoken;
  final List<String> listening;
  final List<String> reading;
  final List<String> writing;

  const CanDoStatements({
    required this.spoken,
    required this.listening,
    required this.reading,
    required this.writing,
  });

  factory CanDoStatements.fromJson(Map<String, dynamic> j) => CanDoStatements(
        spoken: _strList(j['spoken']),
        listening: _strList(j['listening']),
        reading: _strList(j['reading']),
        writing: _strList(j['writing']),
      );
}

class UnitProgressionInfo {
  final int step;
  final String phase;
  final int difficultyScore;
  final String? prerequisite;
  final bool milestone;
  final String? milestoneLabel;

  const UnitProgressionInfo({
    required this.step,
    required this.phase,
    required this.difficultyScore,
    required this.prerequisite,
    required this.milestone,
    required this.milestoneLabel,
  });

  factory UnitProgressionInfo.fromJson(Map<String, dynamic> j) => UnitProgressionInfo(
        step: j['step'] as int,
        phase: j['phase'] as String,
        difficultyScore: j['difficultyScore'] as int,
        prerequisite: j['prerequisite'] as String?,
        milestone: j['milestone'] as bool? ?? false,
        milestoneLabel: j['milestoneLabel'] as String?,
      );
}

/// Curriculum progression metadata (from `UNIT_META` in the source app) —
/// distinct from [UnitMeta] (Phase 1's `unit_meta.json`, used by the Dashboard).
class UnitCurriculumMeta {
  final String id;
  final String cefr;
  final CanDoStatements canDo;
  final UnitProgressionInfo progression;

  const UnitCurriculumMeta({
    required this.id,
    required this.cefr,
    required this.canDo,
    required this.progression,
  });

  factory UnitCurriculumMeta.fromJson(String id, Map<String, dynamic> j) => UnitCurriculumMeta(
        id: id,
        cefr: j['cefr'] as String,
        canDo: CanDoStatements.fromJson(j['canDo'] as Map<String, dynamic>),
        progression: UnitProgressionInfo.fromJson(j['progression'] as Map<String, dynamic>),
      );
}
