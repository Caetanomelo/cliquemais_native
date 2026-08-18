class Phrase {
  // Stable drive_phrases.id from Supabase — used to build the
  // content_completions content_id ("drive:<id>"). Nullable because a
  // stale on-disk cache from before this field existed (see
  // RemoteContentService's fallback-to-cache path) won't have it; callers
  // fall back to a unit+position key in that case.
  final int? id;
  final String en;
  final String pt;
  final String cefr;
  final double rate;

  const Phrase({this.id, required this.en, required this.pt, required this.cefr, required this.rate});

  factory Phrase.fromJson(Map<String, dynamic> j) => Phrase(
        id: j['id'] as int?,
        en: j['en'] as String,
        pt: j['pt'] as String,
        cefr: j['cefr'] as String,
        rate: (j['rate'] as num).toDouble(),
      );
}

class UnitPhrases {
  final int unit;
  final List<Phrase> phrases;
  const UnitPhrases({required this.unit, required this.phrases});

  factory UnitPhrases.fromJson(Map<String, dynamic> j) => UnitPhrases(
        unit: j['unit'] as int,
        phrases: (j['phrases'] as List).map((e) => Phrase.fromJson(e as Map<String, dynamic>)).toList(),
      );
}
