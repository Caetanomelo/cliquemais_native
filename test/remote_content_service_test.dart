import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cliquemais_native/core/services/remote_content_service.dart';

void main() {
  group('RemoteContentService.loadString', () {
    test('fetches the asset from the Netlify-hosted /data/ path', () async {
      Uri? requestedUri;
      final service = RemoteContentService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response('{"units":[]}', 200);
        }),
      );

      final body = await service.loadString('units.json');

      expect(requestedUri.toString(), 'https://clickmaisapp.netlify.app/data/units.json');
      expect(body, '{"units":[]}');
    });

    test('throws on a non-200 response', () async {
      final service = RemoteContentService(
        client: MockClient((request) async => http.Response('not found', 404)),
      );

      expect(() => service.loadString('missing.json'), throwsA(isA<Exception>()));
    });

    test('throws on malformed JSON even with a 200 status', () async {
      final service = RemoteContentService(
        client: MockClient((request) async => http.Response('not json', 200)),
      );

      expect(() => service.loadString('broken.json'), throwsA(isA<FormatException>()));
    });

    test('retries on a 500 and succeeds once the server recovers', () async {
      var callCount = 0;
      final service = RemoteContentService(
        client: MockClient((request) async {
          callCount++;
          if (callCount < 2) return http.Response('server error', 500);
          return http.Response('{"ok":true}', 200);
        }),
      );

      final body = await service.loadString('flaky.json');

      expect(callCount, 2);
      expect(body, '{"ok":true}');
    });

    test('throws after every retry fails on a 500', () async {
      final service = RemoteContentService(
        client: MockClient((request) async => http.Response('server error', 503)),
      );

      expect(() => service.loadString('units.json'), throwsA(isA<Exception>()));
    });
  });
}
