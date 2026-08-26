import 'course_language.dart';

class VocabItem {
  // Stable vocab_items.id from Supabase — needed so the client can
  // record/check per-item completion (content_completions.content_id).
  final int? id;
  final String en;
  final String pt;
  // The literal English word — [en] holds the target-language word once a
  // Lesson/CorpTrack resolves to a non-English target, so emoji lookups
  // (emoji_map.json is English-only) must use this instead.
  final String enBase;
  // Full {en,es,pt} triple, retained so an already-parsed item (e.g. from
  // UnitDataRepository.vocabForUnit, which is unrelated to Lesson blocks and
  // has no raw JSON kept around) can still be re-resolved to a different
  // (target, native) pair via [resolvePair] — same reasoning as
  // Phrase.byLanguage.
  final Map<String, String> byLanguage;

  const VocabItem({
    this.id,
    required this.en,
    required this.pt,
    String? enBase,
    this.byLanguage = const {},
  }) : enBase = enBase ?? en;

  factory VocabItem.fromJson(Map<String, dynamic> j) => VocabItem(
        id: j['id'] as int?,
        en: j['en'] as String,
        pt: j['pt'] as String,
        byLanguage: {
          for (final code in kLanguages)
            if (j[code] is String) code: j[code] as String,
        },
      );

  // Vocab items are stored as flat {en,es,pt} triples (backend migration
  // 038) — this picks [target] as the target-language word and [native] as
  // the native-language explanation, for any of the 6 valid (target,
  // native) pairs. Mirrors WEB_BASE's resolveLessonLanguage vocab branch
  // (`{ en: it[target], pt: it[native], enBase: it.en }`).
  factory VocabItem.forPair(Map<String, dynamic> j, String target, String native) => VocabItem(
        id: j['id'] as int?,
        en: j[target] as String? ?? j['en'] as String,
        pt: j[native] as String? ?? j['pt'] as String,
        enBase: j['en'] as String?,
        byLanguage: {
          for (final code in kLanguages)
            if (j[code] is String) code: j[code] as String,
        },
      );

  /// Re-resolves an already-parsed item to a different (target, native) pair
  /// using the full triple retained in [byLanguage] — for call sites (VPC)
  /// that read items straight from UnitDataRepository instead of through a
  /// Lesson block, so there's no raw JSON left around to re-pick from.
  VocabItem resolvePair(String target, String native) => VocabItem(
        id: id,
        en: byLanguage[target] ?? en,
        pt: byLanguage[native] ?? pt,
        enBase: byLanguage['en'] ?? enBase,
        byLanguage: byLanguage,
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
