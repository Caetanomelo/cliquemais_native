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
    test('uses the en-US result directly when confidently English', () async {
      final langs = <String>[];
      final service = PronunciationAssessmentService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          langs.add(body['lang'] as String);
          return _nBestResponse(display: 'hello world', confidence: 0.9, pronScore: 88);
        }),
      );

      final result = await assessCallTurn(service, [1, 2, 3]);

      expect(result.transcript, 'hello world');
      expect(result.failed, isFalse);
      expect(langs, ['en-US']); // no pt-BR fallback call made
    });

    test('falls back to pt-BR when the en-US pass is not confidently English', () async {
      final langs = <String>[];
      final service = PronunciationAssessmentService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final lang = body['lang'] as String;
          langs.add(lang);
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
      expect(langs, ['en-US', 'pt-BR']);
    });

    test('falls back to pt-BR when the en-US pass throws, and reports the error', () async {
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
      expect(reasons, ['en-US assess failed', 'pt-BR fallback assess failed']);
    });
  });
}
