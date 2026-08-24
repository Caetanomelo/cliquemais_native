/// Course languages with alternate content in the backend, besides English
/// (the base/default, always present). Adding a new language (e.g. 'pt')
/// is ONLY adding it here — no other file in the multilingual rollout
/// should grow a new branch per language code.
const List<String> kCourseOverrideLanguages = ['es'];

const Map<String, String> kCourseLanguageLabels = {'en': 'Inglês', 'es': 'Espanhol'};

/// TTS/STT locale per course language (includes 'en', the base).
const Map<String, String> kCourseLanguageLocale = {'en': 'en-US', 'es': 'es-US'};

String resolveLocale(String courseLanguage) => kCourseLanguageLocale[courseLanguage] ?? 'en-US';

/// Vocab-shaped override items (drive-phrase-style: `{en, pt}` base, a flat
/// `{es: "...", pt: "..."}` override) store the translated text under the
/// language-code key itself, not under `en` — [VocabItem.fromJson]/[Phrase]
/// parsing always reads `en` as "the course-language text", so this remaps
/// `item[code] -> item['en']` before handing the item to those parsers.
/// Same trick WEB_BASE's `resolveLessonLanguage`/`resolveCorpTrackLanguage`
/// use (`Object.assign({}, it, { en: it.es })`).
Map<String, dynamic> remapVocabItemLanguage(Map<String, dynamic> item, String code) {
  if (!item.containsKey(code)) return item;
  // enBase preserves the original English word — emoji_map.json is only ever
  // keyed in English, so emoji lookups can't use `en` once it becomes the
  // course-language word (see [VocabItem.enBase]).
  return {...item, 'en': item[code], 'enBase': item['en']};
}
