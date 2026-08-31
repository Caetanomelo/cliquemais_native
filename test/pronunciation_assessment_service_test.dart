import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cliquemais_native/core/services/pronunciation_assessment_service.dart';

void main() {
  group('PronunciationAssessmentService.assess', () {
    test('parses NBest into a result with low-score words flagged', () async {
      http.Request? captured;
      final service = PronunciationAssessmentService(
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'NBest': [
                {
                  'Confidence': 0.87,
                  'Display': 'hello world',
                  'Words': [
                    {
                      'Word': 'hello',
                      'PronunciationAssessment': {'AccuracyScore': 95, 'ErrorType': 'None'},
                    },
                    {
                      'Word': 'world',
                      'PronunciationAssessment': {'AccuracyScore': 40, 'ErrorType': 'Mispronunciation'},
                    },
                  ],
                  'PronunciationAssessment': {'PronScore': 72.5},
                }
              ],
            }),
            200,
          );
        }),
      );

      final result = await service.assess([1, 2, 3]);

      expect(result, isNotNull);
      expect(result!.recognizedText, 'hello world');
      expect(result.confidence, 0.87);
      expect(result.pronScore, 72.5);
      expect(result.wordCount, 2);
      expect(result.lowScoreWords, hasLength(1));
      expect(result.lowScoreWords.first.word, 'world');
      expect(result.isConfidentEnglish, isTrue);
      expect(result.toFeedbackNote(), contains('world'));

      expect(captured!.url.toString(), 'https://clickmaisapp.netlify.app/.netlify/functions/pronunciation-assess');
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['lang'], 'en-US');
      expect(body['audioBase64'], base64Encode([1, 2, 3]));
    });

    test('returns null when NBest is empty', () async {
      final service = PronunciationAssessmentService(
        client: MockClient((request) async => http.Response(jsonEncode({'NBest': []}), 200)),
      );

      expect(await service.assess([1, 2, 3]), isNull);
    });

    test('returns null when fewer than 2 words were recognized', () async {
      final service = PronunciationAssessmentService(
        client: MockClient((request) async => http.Response(
              jsonEncode({
                'NBest': [
                  {
                    'Confidence': 0.9,
                    'Display': 'hi',
                    'Words': [
                      {
                        'Word': 'hi',
                        'PronunciationAssessment': {'AccuracyScore': 90, 'ErrorType': 'None'},
                      },
                    ],
                    'PronunciationAssessment': {'PronScore': 90.0},
                  }
                ],
              }),
              200,
            )),
      );

      expect(await service.assess([1, 2, 3]), isNull);
    });

    // Regression test for the native-pass "nothing happens when I speak
    // Portuguese" bug: pronunciation-assess.js omits the
    // Pronunciation-Assessment header for the native-language fallback pass
    // (isNativePass=true), and Azure only ever includes the per-word `Words`
    // breakdown when that header was sent. So a real native-pass response
    // never has `Words`, even for a perfectly recognized turn — the old
    // `wordsJson.length < 2` gate made assess() return null every single
    // time for that pass, which the call screen then silently swallowed as
    // "nothing to send" for every Portuguese turn.
    test('falls back to counting words in the recognized text when Azure omits Words (native pass)', () async {
      final service = PronunciationAssessmentService(
        client: MockClient((request) async => http.Response(
              jsonEncode({
                'NBest': [
                  {'Confidence': 0.82, 'Display': 'Como se diz boa noite em inglês'},
                ],
              }),
              200,
              // Without a content-type header, http.Response encodes the body
              // as latin1, mangling the accented text — see the identical
              // note in call_turn_assessor_test.dart's _nBestResponse.
              headers: const {'content-type': 'application/json'},
            )),
      );

      final result = await service.assess([1, 2, 3], lang: 'pt-BR');

      expect(result, isNotNull);
      expect(result!.recognizedText, 'Como se diz boa noite em inglês');
      expect(result.wordCount, 7);
      expect(result.lowScoreWords, isEmpty);
    });

    test('still returns null when the Words-less text is under 2 words (native pass)', () async {
      final service = PronunciationAssessmentService(
        client: MockClient((request) async => http.Response(
              jsonEncode({
                'NBest': [
                  {'Confidence': 0.7, 'Display': 'oi'},
                ],
              }),
              200,
            )),
      );

      expect(await service.assess([1, 2, 3], lang: 'pt-BR'), isNull);
    });

    test('throws when the function returns a non-200 status', () async {
      final service = PronunciationAssessmentService(
        client: MockClient((request) async => http.Response('server error', 500)),
      );

      expect(() => service.assess([1, 2, 3]), throwsA(isA<Exception>()));
    });
  });
}
