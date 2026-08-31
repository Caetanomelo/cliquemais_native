import 'dart:convert';
import 'package:http/http.dart' as http;

import 'netlify_post_json.dart';

class PronWord {
  final String word;
  final double accuracyScore;
  final String errorType;
  const PronWord({required this.word, required this.accuracyScore, required this.errorType});
}

/// Result of one Azure Speech call, either an `en-US` pronunciation
/// assessment pass or a plain `pt-BR` transcription fallback pass.
class PronunciationResult {
  final String recognizedText;
  final double confidence;
  final double pronScore;
  final int wordCount;
  final List<PronWord> lowScoreWords;

  const PronunciationResult({
    required this.recognizedText,
    required this.confidence,
    required this.pronScore,
    required this.wordCount,
    required this.lowScoreWords,
  });

  /// True when this looks like a genuine English attempt worth scoring,
  /// not noise or a Portuguese turn misheard by the en-US recognizer.
  bool get isConfidentEnglish => confidence >= 0.5 && wordCount >= 2;

  /// Builds a `[Pronunciation feedback: ...]` note to append to the message
  /// sent to the tutor, or '' if there's nothing worth flagging.
  String toFeedbackNote() {
    if (!isConfidentEnglish || lowScoreWords.isEmpty) return '';
    final words = lowScoreWords.take(3).map((w) => w.word).join(', ');
    return '[Pronunciation feedback: score ${pronScore.round()}/100. Palavras a corrigir: $words]';
  }
}

/// Proxies raw call-turn audio through `/.netlify/functions/pronunciation-assess`
/// (Azure Speech), mirroring [AiTutorService]'s http pattern. Any failure here
/// must be caught by the caller and treated as "no result this turn" — never
/// block the underlying chat turn.
class PronunciationAssessmentService {
  final http.Client _client;

  PronunciationAssessmentService({http.Client? client}) : _client = client ?? http.Client();

  Future<PronunciationResult?> assess(List<int> wavBytes, {String lang = 'en-US'}) async {
    final json = await postJson(
      _client,
      'pronunciation-assess',
      {'audioBase64': base64Encode(wavBytes), 'lang': lang},
      errorLabel: 'Pronunciation assessment',
    );
    final nBest = json['NBest'] as List?;
    if (nBest == null || nBest.isEmpty) return null;
    final best = nBest.first as Map<String, dynamic>;

    final confidence = (best['Confidence'] as num?)?.toDouble() ?? 1.0;
    final recognizedText = (best['Display'] as String?) ?? (best['Lexical'] as String?) ?? '';
    final wordsJson = (best['Words'] as List?) ?? const [];
    // Azure only includes the per-word `Words` breakdown when the
    // Pronunciation-Assessment header was sent with the request (see
    // pronunciation-assess.js's `isNativePass`) — the native-language
    // fallback pass deliberately omits that header (scoring pronunciation of
    // the student's own native language isn't meaningful), so `Words` is
    // always empty there regardless of what was said. Gating on its length
    // used to make that pass return null for every single turn. Count words
    // in the recognized text itself when Azure didn't return word-level
    // detail, so a real transcript still counts as a real result.
    final textWordCount = recognizedText.trim().isEmpty
        ? 0
        : recognizedText.trim().split(RegExp(r'\s+')).length;
    final wordCount = wordsJson.isNotEmpty ? wordsJson.length : textWordCount;
    if (wordCount < 2) return null;

    final pa = best['PronunciationAssessment'] as Map<String, dynamic>? ?? const {};
    final pronScore = (pa['PronScore'] as num?)?.toDouble() ?? 0.0;

    final lowScoreWords = <PronWord>[];
    for (final w in wordsJson) {
      final wm = w as Map<String, dynamic>;
      final wpa = wm['PronunciationAssessment'] as Map<String, dynamic>? ?? const {};
      final accuracy = (wpa['AccuracyScore'] as num?)?.toDouble() ?? 100.0;
      final errorType = wpa['ErrorType'] as String? ?? 'None';
      if (accuracy < 80 || errorType == 'Mispronunciation' || errorType == 'Omission') {
        lowScoreWords.add(PronWord(word: wm['Word'] as String? ?? '', accuracyScore: accuracy, errorType: errorType));
      }
    }

    return PronunciationResult(
      recognizedText: recognizedText,
      confidence: confidence,
      pronScore: pronScore,
      wordCount: wordCount,
      lowScoreWords: lowScoreWords,
    );
  }

  void dispose() => _client.close();
}
