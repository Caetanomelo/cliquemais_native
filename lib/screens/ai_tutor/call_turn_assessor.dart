import '../../core/services/pronunciation_assessment_service.dart';

// Closed-class function words (articles, pronouns, prepositions, common
// question/greeting words) used to sanity-check which language a recognized
// string actually looks like it belongs to. Two deliberate exclusions:
// - Each language's own name ("english"/"inglês", "español"/"espanhol",
//   etc.) — those are exactly the words Azure's forced-decode most often
//   mangles into a near-homophone of the *wrong* locale (e.g. Portuguese
//   "inglês" decoded through the en-US model comes back as something like
//   "English"), which would otherwise make garbage primary-language output
//   look plausible.
// - Words spelled identically in Spanish and Portuguese ("como", "se",
//   "que", "de", "tu", "este", "esta", "era", "sabe", "tres", bare "a") —
//   keeping those would let genuine Portuguese text "pass" as plausible
//   Spanish (and vice versa) purely because the two languages share so much
//   closed-class vocabulary, defeating the whole point of the check for
//   that language pair.
const Map<String, Set<String>> _languageFunctionWords = {
  'en': {
    'the', 'is', 'are', 'you', 'your', 'how', 'do', 'does', 'say', 'said',
    'in', 'to', 'what', 'i', 'we', 'can', 'this', 'that', 'and', 'of', 'a',
    'an', 'for', 'with', 'on', 'at', 'was', 'were', 'have', 'has', 'my',
    'me', 'good', 'night', 'morning', 'hello', 'hi', 'thanks', 'thank',
    'please', 'yes', 'no', 'want', 'like', 'know', 'think', 'speak', 'one',
    'two', 'three', 'not', 'it', 'be', 'am',
  },
  'es': {
    'el', 'la', 'los', 'las', 'es', 'son', 'cómo', 'dice', 'en', 'qué',
    'yo', 'tú', 'usted', 'puede', 'puedo', 'y', 'un', 'una', 'para', 'con',
    'al', 'fue', 'tengo', 'tiene', 'mi', 'buenas', 'noches', 'buenos',
    'dias', 'días', 'hola', 'gracias', 'si', 'sí', 'no', 'quiero', 'quiere',
    'pienso', 'hablar', 'uno', 'dos',
  },
  'pt': {
    'o', 'a', 'os', 'as', 'é', 'sao', 'são', 'diz', 'em', 'eu', 'voce',
    'você', 'pode', 'posso', 'isso', 'e', 'um', 'uma', 'para', 'com', 'no',
    'na', 'foi', 'tenho', 'tem', 'meu', 'minha', 'boa', 'noite', 'bom',
    'dia', 'ola', 'olá', 'oi', 'obrigado', 'obrigada', 'sim', 'nao', 'não',
    'quero', 'quer', 'sei', 'penso', 'falar', 'dois', 'três',
  },
};

/// Rough "does this text actually look like [langCode] words" check — a
/// complement to Azure's acoustic confidence score, which reflects how well
/// audio matches *some* phoneme sequence in the requested locale, not
/// whether the resulting words are real content in that language. Used to
/// catch cases where a forced-decode pass's confidence alone would win the
/// comparison in [assessCallTurn] despite producing nonsense. Requires at
/// least 2 hits (not just 1) on longer text since the es/pt overlap removal
/// above thins the dictionaries enough that a single stray match isn't
/// strong evidence on its own.
bool _looksLikeLanguage(String text, String langCode) {
  final tokens = text
      .toLowerCase()
      .split(RegExp(r'[^a-zà-öø-ÿ]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (tokens.isEmpty) return false;
  final dict = _languageFunctionWords[langCode] ?? const <String>{};
  final hits = tokens.where(dict.contains).length;
  if (tokens.length <= 2) return hits >= 1;
  return hits >= 2 && hits / tokens.length >= 0.25;
}

/// Result of assessing one turn's raw audio.
class CallTurnAssessment {
  final String transcript;
  final String feedback;
  final bool failed;
  // Only set when the en-US pass was confidently English — lets callers
  // that want a score card (the inline chat mic) render one, while callers
  // that only care about the transcript (the call screen) ignore them.
  final double? pronScore;
  final List<PronWord> lowScoreWords;
  const CallTurnAssessment({
    required this.transcript,
    required this.feedback,
    this.failed = false,
    this.pronScore,
    this.lowScoreWords = const [],
  });
}

/// Runs both the course-language pronunciation-assessment pass ([primaryLang],
/// e.g. 'en-US' or 'es-US') and a plain [nativeLang] transcription pass, and
/// picks whichever one Azure was actually more confident about — extracted
/// out of AiTutorCallScreen so this decision can be exercised directly
/// against a mocked Netlify response instead of needing the full screen +
/// record/TTS platform channels wired up.
///
/// Both passes always run (not "try primary, fall back only if unconfident")
/// because Azure's [primaryLang] recognizer force-decodes ANY audio into
/// [primaryLang] words — a Portuguese turn read through the en-US model
/// routinely comes back with `confidence >= 0.5` even though the words are
/// garbage, since Confidence reflects "how well the audio matches the
/// recognized text acoustically", not "is this actually English content".
/// Trusting that in isolation misidentified most Portuguese turns as
/// confident English, sent the garbled English transcript to the tutor, and
/// made it reply (and TTS) in English for turns spoken entirely in
/// Portuguese. Comparing both passes' confidence picks the language that
/// actually matches what was said.
///
/// `failed` is only true when both passes threw (Azure
/// unreachable/misconfigured), as opposed to a legitimate empty/silent turn,
/// so the caller can tell "nothing to send" apart from "something went
/// wrong" and surface that to the user.
Future<CallTurnAssessment> assessCallTurn(
  PronunciationAssessmentService pronunciation,
  List<int> wavBytes, {
  String primaryLang = 'en-US',
  String nativeLang = 'pt-BR',
  void Function(Object error, StackTrace stack, {required String reason})?
  onError,
}) async {
  PronunciationResult? primaryResult;
  PronunciationResult? nativeResult;
  Object? primaryError;
  Object? nativeError;

  await Future.wait([
    pronunciation
        .assess(wavBytes, lang: primaryLang, isNativePass: false)
        .then((r) => primaryResult = r)
        .catchError((Object e, StackTrace st) {
          primaryError = e;
          onError?.call(e, st, reason: '$primaryLang assess failed');
          return null;
        }),
    pronunciation
        .assess(wavBytes, lang: nativeLang, isNativePass: true)
        .then((r) => nativeResult = r)
        .catchError((Object e, StackTrace st) {
          nativeError = e;
          onError?.call(e, st, reason: '$nativeLang assess failed');
          return null;
        }),
  ]);

  if (primaryResult == null && nativeResult == null) {
    return CallTurnAssessment(
      transcript: '',
      feedback: '',
      failed: primaryError != null && nativeError != null,
    );
  }

  // Confidence alone isn't enough: Azure's primaryLang recognizer routinely
  // reports confidence >= 0.5 for forced-decoded garbage (see class doc), so
  // a native turn can occasionally out-score the pt-BR pass on confidence
  // even though the primaryLang text is nonsense. Cross-check against
  // whether each pass's recognized text actually looks like real words of
  // its own language — if primary's text doesn't look like primaryLang and
  // native's text does look like nativeLang, native wins regardless of the
  // raw confidence numbers.
  //
  // Crucially, primary must clear the plausibility bar on its own whenever
  // the native pass is unavailable (threw, or returned too few words to
  // parse) — on real devices the pt-BR pass regularly fails outright for a
  // turn spoken entirely in Portuguese (network hiccup, Azure returning an
  // empty NBest for a phrase it's less confident about), and that used to
  // fall through this whole check via the `nativeResult == null` shortcut,
  // silently re-opening the exact bug this function exists to close: a
  // "confidently English" (per Azure's acoustic score) but nonsense
  // primaryLang transcript sent straight to the tutor.
  final primaryLangCode = primaryLang.split('-').first;
  final nativeLangCode = nativeLang.split('-').first;
  final primaryPlausible =
      primaryResult != null && _looksLikeLanguage(primaryResult!.recognizedText, primaryLangCode);
  final nativePlausible =
      nativeResult != null && _looksLikeLanguage(nativeResult!.recognizedText, nativeLangCode);
  final usePrimary =
      primaryResult != null &&
      primaryResult!.isConfidentEnglish &&
      (nativeResult == null || primaryResult!.confidence >= nativeResult!.confidence) &&
      (primaryPlausible || (nativeResult != null && !nativePlausible));

  if (usePrimary) {
    final p = primaryResult!;
    return CallTurnAssessment(
      transcript: p.recognizedText,
      feedback: p.toFeedbackNote(),
      pronScore: p.pronScore,
      lowScoreWords: p.lowScoreWords,
    );
  }
  return CallTurnAssessment(
    transcript: nativeResult?.recognizedText ?? '',
    feedback: '',
  );
}
