class UnitMeta {
  final int unit;
  final String cefr;
  final int step;
  final bool milestone;
  final String? milestoneLabel;
  final String phase;

  const UnitMeta({
    required this.unit,
    required this.cefr,
    required this.step,
    required this.milestone,
    required this.milestoneLabel,
    required this.phase,
  });

  factory UnitMeta.fromJson(Map<String, dynamic> j) => UnitMeta(
        unit: j['unit'] as int,
        cefr: j['cefr'] as String,
        step: j['step'] as int,
        milestone: j['milestone'] as bool,
        milestoneLabel: j['milestoneLabel'] as String?,
        phase: j['phase'] as String,
      );
}
