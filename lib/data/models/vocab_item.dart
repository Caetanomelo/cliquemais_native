class VocabItem {
  final String en;
  final String pt;
  const VocabItem({required this.en, required this.pt});

  factory VocabItem.fromJson(Map<String, dynamic> j) => VocabItem(
        en: j['en'] as String,
        pt: j['pt'] as String,
      );
}

class UnitVocab {
  final int unit;
  final List<VocabItem> items;
  const UnitVocab({required this.unit, required this.items});

  factory UnitVocab.fromJson(Map<String, dynamic> j) => UnitVocab(
        unit: j['unit'] as int,
        items: (j['items'] as List).map((e) => VocabItem.fromJson(e as Map<String, dynamic>)).toList(),
      );
}
