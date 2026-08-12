import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cliquemais_native/core/services/ai_tutor_service.dart';

void main() {
  group('AiTutorService.send', () {
    test('posts the system prompt, history and message, returns the reply', () async {
      http.Request? captured;
      final service = AiTutorService(
        client: MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode({'reply': 'Hello!'}), 200);
        }),
      );

      final reply = await service.send(
        systemPrompt: 'You are a tutor',
        history: const [AiChatMessage(role: 'user', content: 'oi')],
        userMessage: 'tudo bem?',
      );

      expect(reply, 'Hello!');
      expect(captured!.url.toString(), 'https://clickmaisapp.netlify.app/.netlify/functions/ai-chat');
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['systemPrompt'], 'You are a tutor');
      expect(body['userMessage'], 'tudo bem?');
      expect(body['history'], [
        {'role': 'user', 'content': 'oi'}
      ]);
    });

    test('throws when the function returns a non-200 status', () async {
      final service = AiTutorService(
        client: MockClient((request) async => http.Response('server error', 500)),
      );

      expect(
        () => service.send(systemPrompt: '', history: const [], userMessage: 'oi'),
        throwsA(isA<Exception>()),
      );
    });

    test('returns an empty string when the reply field is missing', () async {
      final service = AiTutorService(
        client: MockClient((request) async => http.Response(jsonEncode({}), 200)),
      );

      final reply = await service.send(systemPrompt: '', history: const [], userMessage: 'oi');
      expect(reply, '');
    });
  });
}
