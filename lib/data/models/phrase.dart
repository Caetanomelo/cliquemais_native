import 'course_language.dart';

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
  // Course-language text override, keyed by kCourseOverrideLanguages code
  // (e.g. 'es') — the raw JSON stores it flat as `json[code]`, not nested.
  final Map<String, String> byLanguage;

  const Phrase({
    this.id,
    required this.en,
    required this.pt,
    required this.cefr,
    required this.rate,
    this.byLanguage = const {},
  });

  String textFor(String lang) => lang == 'en' ? en : (byLanguage[lang] ?? en);

  factory Phrase.fromJson(Map<String, dynamic> j) {
    final byLanguage = <String, String>{};
    for (final code in kCourseOverrideLanguages) {
      final v = j[code] as String?;
      if (v != null) byLanguage[code] = v;
    }
    return Phrase(
      id: j['id'] as int?,
      en: j['en'] as String,
      pt: j['pt'] as String,
      cefr: j['cefr'] as String,
      rate: (j['rate'] as num).toDouble(),
      byLanguage: byLanguage,
    );
  }
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
