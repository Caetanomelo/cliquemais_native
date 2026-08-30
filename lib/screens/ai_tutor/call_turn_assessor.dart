import '../../core/services/pronunciation_assessment_service.dart';

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
        .assess(wavBytes, lang: primaryLang)
        .then((r) => primaryResult = r)
        .catchError((Object e, StackTrace st) {
          primaryError = e;
          onError?.call(e, st, reason: '$primaryLang assess failed');
          return null;
        }),
    pronunciation
        .assess(wavBytes, lang: nativeLang)
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

  final usePrimary =
      primaryResult != null &&
      primaryResult!.isConfidentEnglish &&
      (nativeResult == null || primaryResult!.confidence >= nativeResult!.confidence);

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
