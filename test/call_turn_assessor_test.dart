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
    // Without a content-type header, http.Response encodes the body as
    // latin1, mangling the accented display text used in the pt-BR
    // gibberish regression tests when postJson later utf8-decodes the raw
    // bytes. A JSON content-type (matching what the real Netlify function
    // sends) makes http.Response use utf8, like production traffic does.
    headers: const {'content-type': 'application/json'},
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

    // Regression test for the second bug report: user spoke entirely in
    // Portuguese ("Como se diz boa noite em inglês") in an English-course
    // call. Azure's en-US pass force-decoded it into plausible-sounding but
    // meaningless English gibberish with confidence >= the pt-BR pass's
    // confidence, so the old confidence-only comparison picked the garbled
    // English text. The function-word plausibility check should catch that
    // the "English" text isn't real English and fall back to pt-BR.
    test('prefers pt-BR when en-US confidence wins but the en-US text is gibberish', () async {
      final service = PronunciationAssessmentService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final lang = body['lang'] as String;
          if (lang == 'en-US') {
            return _nBestResponse(
              display: 'Black Oma CGS born rich English',
              confidence: 0.65,
              pronScore: 40,
              wordCount: 6,
            );
          }
          return _nBestResponse(
            display: 'Como se diz boa noite em inglês',
            confidence: 0.55,
            pronScore: 0,
            wordCount: 7,
          );
        }),
      );

      final result = await assessCallTurn(service, [1, 2, 3]);

      expect(result.transcript, 'Como se diz boa noite em inglês');
      expect(result.feedback, '');
      expect(result.failed, isFalse);
    });

    // Same failure mode, Spanish course this time (the other reported
    // screenshot): "Como se diz boa noite em espanhol" force-decoded through
    // es-US.
    test('prefers pt-BR when es-US confidence wins but the es-US text is gibberish', () async {
      final service = PronunciationAssessmentService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final lang = body['lang'] as String;
          if (lang == 'es-US') {
            return _nBestResponse(
              display: 'Cómo se llevó a noise',
              confidence: 0.6,
              pronScore: 35,
              wordCount: 5,
            );
          }
          return _nBestResponse(
            display: 'Como se diz boa noite em espanhol',
            confidence: 0.5,
            pronScore: 0,
            wordCount: 7,
          );
        }),
      );

      final result = await assessCallTurn(
        service,
        [1, 2, 3],
        primaryLang: 'es-US',
      );

      expect(result.transcript, 'Como se diz boa noite em espanhol');
      expect(result.feedback, '');
      expect(result.failed, isFalse);
    });

    // Regression test for the real-device follow-up to the gibberish bug:
    // the pt-BR pass can outright fail (throw, or Azure returning too few
    // words to parse) for a turn spoken entirely in Portuguese, while the
    // en-US pass still comes back "confidently English" per Azure's own
    // acoustic score on forced-decoded nonsense. The old check only ran the
    // plausibility comparison when both passes succeeded, so a failed
    // native pass silently let garbage English through again. Now primary
    // must clear the plausibility bar on its own whenever native is
    // unavailable — since neither pass produced anything usable here, the
    // turn is dropped (empty transcript) rather than sent to the tutor as
    // English.
    test('drops the turn when the en-US text is gibberish and the pt-BR pass fails outright', () async {
      final reasons = <String>[];
      final service = PronunciationAssessmentService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final lang = body['lang'] as String;
          if (lang == 'en-US') {
            return _nBestResponse(
              display: 'Ola como messages bowenoid each English',
              confidence: 0.6,
              pronScore: 30,
              wordCount: 6,
            );
          }
          return http.Response('server error', 500);
        }),
      );

      final result = await assessCallTurn(
        service,
        [1, 2, 3],
        onError: (e, st, {required reason}) => reasons.add(reason),
      );

      expect(result.transcript, '');
      expect(result.failed, isFalse);
      expect(reasons, ['pt-BR assess failed']);
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
