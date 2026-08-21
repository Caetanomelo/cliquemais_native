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

/// Runs the en-US pronunciation-assessment pass first; falls back to a plain
/// pt-BR transcription pass when the en-US pass isn't confidently English
/// (background noise, or the turn was in Portuguese) — extracted out of
/// AiTutorCallScreen so this fallback decision can be exercised directly
/// against a mocked Netlify response instead of needing the full screen +
/// record/TTS platform channels wired up. `failed` is only true when both
/// passes threw (Azure unreachable/misconfigured), as opposed to a
/// legitimate empty/silent turn, so the caller can tell "nothing to send"
/// apart from "something went wrong" and surface that to the user.
Future<CallTurnAssessment> assessCallTurn(
  PronunciationAssessmentService pronunciation,
  List<int> wavBytes, {
  void Function(Object error, StackTrace stack, {required String reason})?
  onError,
}) async {
  try {
    final enResult = await pronunciation.assess(wavBytes, lang: 'en-US');
    if (enResult != null && enResult.isConfidentEnglish) {
      return CallTurnAssessment(
        transcript: enResult.recognizedText,
        feedback: enResult.toFeedbackNote(),
        pronScore: enResult.pronScore,
        lowScoreWords: enResult.lowScoreWords,
      );
    }
    final ptResult = await pronunciation.assess(wavBytes, lang: 'pt-BR');
    return CallTurnAssessment(
      transcript: ptResult?.recognizedText ?? '',
      feedback: '',
    );
  } catch (e, st) {
    onError?.call(e, st, reason: 'en-US assess failed');
    try {
      final ptResult = await pronunciation.assess(wavBytes, lang: 'pt-BR');
      return CallTurnAssessment(
        transcript: ptResult?.recognizedText ?? '',
        feedback: '',
      );
    } catch (e2, st2) {
      onError?.call(e2, st2, reason: 'pt-BR fallback assess failed');
      return const CallTurnAssessment(
        transcript: '',
        feedback: '',
        failed: true,
      );
    }
  }
}
