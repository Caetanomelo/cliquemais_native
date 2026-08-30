import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cliquemais_native/core/services/pronunciation_assessment_service.dart';
import 'package:cliquemais_native/screens/ai_tutor/call_turn_assessor.dart';

http.Response _nBestResponse({
  required String display,
  required double confidence,
  required double pronScore,
  int wordCount = 2,
}) {
  return http.Response(
    jsonEncode({
      'NBest': [
        {
          'Confidence': confidence,
          'Display': display,
          'Words': List.generate(
            wordCount,
            (i) => {
              'Word': 'w$i',
              'PronunciationAssessment': {'AccuracyScore': 95, 'ErrorType': 'None'},
            },
          ),
          'PronunciationAssessment': {'PronScore': pronScore},
        }
      ],
    }),
    200,
  );
}

void main() {
  group('assessCallTurn', () {
    test('uses the en-US result when confidently English and more confident than the native pass', () async {
      final langs = <String>[];
      final service = PronunciationAssessmentService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final lang = body['lang'] as String;
          langs.add(lang);
          if (lang == 'en-US') {
            return _nBestResponse(display: 'hello world', confidence: 0.9, pronScore: 88);
          }
          return _nBestResponse(display: 'oi', confidence: 0.3, pronScore: 0);
        }),
      );

      final result = await assessCallTurn(service, [1, 2, 3]);

      expect(result.transcript, 'hello world');
      expect(result.failed, isFalse);
      expect(langs, unorderedEquals(['en-US', 'pt-BR'])); // both passes always run now
    });

    test('falls back to pt-BR when the en-US pass is not confidently English', () async {
      final service = PronunciationAssessmentService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final lang = body['lang'] as String;
          if (lang == 'en-US') {
            return _nBestResponse(display: 'uh', confidence: 0.1, pronScore: 10);
          }
          return _nBestResponse(display: 'oi tudo bem', confidence: 0.95, pronScore: 0);
        }),
      );

      final result = await assessCallTurn(service, [1, 2, 3]);

      expect(result.transcript, 'oi tudo bem');
      expect(result.feedback, '');
      expect(result.failed, isFalse);
    });

    // Regression test for the reported bug: Azure's en-US recognizer
    // force-decodes Portuguese audio into plausible-looking English words
    // with confidence >= 0.5, so a fixed threshold alone misidentified most
    // Portuguese turns as confident English and made the tutor reply (and
    // TTS) in English. Comparing against the native pass's confidence fixes
    // it: pt-BR should win whenever it's the better match, even when en-US
    // clears the bare 0.5 bar.
    test('prefers the more-confident pt-BR pass even when en-US clears the confidence bar', () async {
      final service = PronunciationAssessmentService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final lang = body['lang'] as String;
          if (lang == 'en-US') {
            // Misheard Portuguese, but still >= the 0.5 "confident English" bar.
            return _nBestResponse(display: 'oh two bang', confidence: 0.6, pronScore: 40, wordCount: 3);
          }
          return _nBestResponse(display: 'oi, tudo bem?', confidence: 0.85, pronScore: 0, wordCount: 3);
        }),
      );

      final result = await assessCallTurn(service, [1, 2, 3]);

      expect(result.transcript, 'oi, tudo bem?');
      expect(result.feedback, '');
      expect(result.failed, isFalse);
    });

    test('uses the pt-BR result when the en-US pass throws, and reports the error', () async {
      final reasons = <String>[];
      final service = PronunciationAssessmentService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['lang'] == 'en-US') {
            return http.Response('server error', 500);
          }
          return _nBestResponse(display: 'oi', confidence: 0.9, pronScore: 0);
        }),
      );

      final result = await assessCallTurn(
        service,
        [1, 2, 3],
        onError: (e, st, {required reason}) => reasons.add(reason),
      );

      expect(result.transcript, 'oi');
      expect(result.failed, isFalse);
      expect(reasons, ['en-US assess failed']);
    });

    test('reports failed=true and both reasons when every pass throws', () async {
      final reasons = <String>[];
      final service = PronunciationAssessmentService(
        client: MockClient((request) async => http.Response('server error', 500)),
      );

      final result = await assessCallTurn(
        service,
        [1, 2, 3],
        onError: (e, st, {required reason}) => reasons.add(reason),
      );

      expect(result.transcript, '');
      expect(result.failed, isTrue);
      expect(reasons, unorderedEquals(['en-US assess failed', 'pt-BR assess failed']));
    });
  });
}
