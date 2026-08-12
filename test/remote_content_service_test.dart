import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:cliquemais_native/core/services/remote_content_service.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final String path;
  _FakePathProvider(this.path);

  @override
  Future<String?> getApplicationCachePath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PathProviderPlatform.instance = _FakePathProvider(Directory.systemTemp.createTempSync('rcs_test_').path);
  });

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

    test('throws on a non-200 response with no cache to fall back to', () async {
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

    test('falls back to the on-disk cache when every retry fails', () async {
      final flakyClient = MockClient((request) async => http.Response('{"cached":true}', 200));
      final firstService = RemoteContentService(client: flakyClient);
      await firstService.loadString('units.json'); // populates the disk cache

      final downService = RemoteContentService(
        client: MockClient((request) async => http.Response('server error', 503)),
      );

      final body = await downService.loadString('units.json');

      expect(body, '{"cached":true}');
    });
  });
}
