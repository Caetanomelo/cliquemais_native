/// Course languages with alternate content in the backend, besides English
/// (the base/default, always present). Adding a new language (e.g. 'pt')
/// is ONLY adding it here — no other file in the multilingual rollout
/// should grow a new branch per language code.
const List<String> kCourseOverrideLanguages = ['es'];

const Map<String, String> kCourseLanguageLabels = {'en': 'Inglês', 'es': 'Espanhol'};

/// TTS/STT locale per course language (includes 'en', the base).
const Map<String, String> kCourseLanguageLocale = {'en': 'en-US', 'es': 'es-US'};

String resolveLocale(String courseLanguage) => kCourseLanguageLocale[courseLanguage] ?? 'en-US';
