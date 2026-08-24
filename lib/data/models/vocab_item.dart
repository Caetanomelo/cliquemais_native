import 'course_language.dart';

class VocabItem {
  // Stable vocab_items.id from Supabase — see the same field on [Phrase]
  // for why it's nullable and what it's used for.
  final int? id;
  final String en;
  final String pt;
  // Course-language text override, keyed by kCourseOverrideLanguages code.
  // No-op today (vocab_items.json has no override column yet in the
  // database), but ready for when it does — same pattern as [Phrase].
  final Map<String, String> byLanguage;

  const VocabItem({this.id, required this.en, required this.pt, this.byLanguage = const {}});

  String textFor(String lang) => lang == 'en' ? en : (byLanguage[lang] ?? en);

  factory VocabItem.fromJson(Map<String, dynamic> j) {
    final byLanguage = <String, String>{};
    for (final code in kCourseOverrideLanguages) {
      final v = j[code] as String?;
      if (v != null) byLanguage[code] = v;
    }
    return VocabItem(
      id: j['id'] as int?,
      en: j['en'] as String,
      pt: j['pt'] as String,
      byLanguage: byLanguage,
    );
  }
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
