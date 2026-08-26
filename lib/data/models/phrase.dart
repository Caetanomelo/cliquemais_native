import 'course_language.dart';

class Phrase {
  // Stable drive_phrases.id from Supabase — used to build the
  // content_completions content_id ("drive:<id>"). Nullable because a
  // stale on-disk cache from before this field existed (see
  // RemoteContentService's fallback-to-cache path) won't have it; callers
  // fall back to a unit+position key in that case.
  final int? id;
  final String cefr;
  final double rate;
  // Tripla completa {en, es, pt}.
  final Map<String, String> byLanguage;

  const Phrase({this.id, required this.byLanguage, required this.cefr, required this.rate});

  String get en => byLanguage['en'] ?? '';
  String get pt => byLanguage['pt'] ?? '';

  factory Phrase.fromJson(Map<String, dynamic> j) {
    final byLanguage = <String, String>{
      for (final code in kLanguages)
        if (j[code] is String) code: j[code] as String,
    };
    return Phrase(id: j['id'] as int?, byLanguage: byLanguage, cefr: j['cefr'] as String, rate: (j['rate'] as num).toDouble());
  }

  // Par (target, native): mesma tripla, so troca qual chave cai em [en]
  // (texto alvo) e [pt] (explicacao nativa) do resultado -- mesma resolucao
  // de vocab/convo (pickTarget/pickExplanation simetricos). Os valores
  // explicitos de en/pt precisam sobrescrever a tripla original -- por isso
  // o spread de [byLanguage] vem primeiro no merge.
  Phrase forPair(String target, String native) => Phrase(
        id: id,
        cefr: cefr,
        rate: rate,
        byLanguage: {...byLanguage, 'en': byLanguage[target] ?? en, 'pt': byLanguage[native] ?? pt},
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
