class Phrase {
  final String en;
  final String pt;
  final String cefr;
  final double rate;

  const Phrase({required this.en, required this.pt, required this.cefr, required this.rate});

  factory Phrase.fromJson(Map<String, dynamic> j) => Phrase(
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
