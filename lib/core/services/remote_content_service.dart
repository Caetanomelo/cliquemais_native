import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../netlify_config.dart';

/// Wraps a transient (network error, timeout, 5xx) failure so [loadString]
/// knows to retry it — a 4xx or a malformed payload never becomes valid by
/// retrying, so those propagate immediately instead.
class _RetryableException implements Exception {
  final Object cause;
  _RetryableException(this.cause);
  @override
  String toString() => cause.toString();
}

/// Fetches the `/data/*.json` content files from the Netlify-hosted API
/// (backed by Supabase). Transient failures (timeouts, network errors, 5xx)
/// are retried with backoff; if every attempt still fails, [loadString]
/// throws — the app is online-only by design and never serves stale or
/// cached content in place of a live response.
class RemoteContentService {
  final http.Client _client;
  static const _maxAttempts = 3;
  static const _retryBaseDelay = Duration(milliseconds: 400);

  RemoteContentService({http.Client? client}) : _client = client ?? http.Client();

  Future<String> loadString(String asset, {Map<String, String>? query}) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        return await _fetchOnce(asset, query);
      } on _RetryableException catch (e) {
        lastError = e.cause;
        if (attempt < _maxAttempts) {
          await Future.delayed(_retryBaseDelay * attempt);
        }
      } catch (e) {
        lastError = e;
        break;
      }
    }

    throw lastError!;
  }

  Future<String> _fetchOnce(String asset, Map<String, String>? query) async {
    final uri = Uri.parse('${NetlifyConfig.baseUrl}/data/$asset')
        .replace(queryParameters: (query == null || query.isEmpty) ? null : query);
    http.Response res;
    try {
      res = await _client.get(uri).timeout(const Duration(seconds: 15));
    } catch (e) {
      throw _RetryableException(e);
    }
    if (res.statusCode >= 500) {
      throw _RetryableException(Exception('Failed to load $asset: HTTP ${res.statusCode}'));
    }
    if (res.statusCode != 200) {
      throw Exception('Failed to load $asset: HTTP ${res.statusCode}');
    }
    jsonDecode(res.body); // sanity check — surface malformed payloads early
    return res.body;
  }

  void dispose() => _client.close();
}
